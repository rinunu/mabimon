# -*- coding: utf-8 -*-

require "filter"

UNKNOWN = "★不明"

# 基本的な正規化を行う
# - 記号と英数字を全角 => 半角
# - 前後のスペースを削除
class BasicFilter < ValueFilter
  def process(value, options)
    raise "value: #{options[:column]}" unless value
    value.tr("`：０-９Ａ-Ｚａ-ｚ（）？　／－−", "':0-9A-Za-z()? /ーー").gsub("??", "?").
      gsub(/[～〜]/, "~").
      gsub("(?)", "?").strip
  end
end

# あ,い,う を 「あ」「い」「う」に分解し、リストに変換する
# 
# - ()や '' でくくられているものは分解しない
class SplitFilter < ValueFilter
  def initialize(separator = /[、,，\n・\/]\s*/)
    @separator = separator
  end
  
  def process(value, options)
    # もっと素直にできないかな。。
    
    value = value.gsub(@separator, "<sep>")

    # 区切るべきではないものをエスケープする
    # () etc. に囲まれた <sep>
    value = value.gsub(/(\(.*?\))/){|a| a.gsub('<sep>', '/')}
    value = value.gsub(/('.*?')/){|a| a.gsub('<sep>', '/')}
    value = value.gsub(/(`.*?`)/){|a| a.gsub('<sep>', '/')}
    
    value.split("<sep>")
  end
end

# ファイルに記述された設定をもとに、置換を行うフィルタ
# ファイルフォーマットは CSV。
# 1レコードの先頭カラムが置換後の文字列、それ以降のカラムは置換前文字列
class ReplaceFilter < ValueFilter
  def initialize(path)
    raise "path" unless path
    @path = path
    @hash = {}
    require "csv"
    CSV.open(@path, 'r') do |row|
      next unless row.size >= 2
      after = row.shift
      for before in row
        before = Regexp.new before
        @hash[before] = after
      end
    end
  end

  def process(value, options)
    for before, after in @hash
      value = value.gsub(before, after)
    end
    value
  end
end

# 名前を統一するためのフィルタ
# Names に存在するものはその正式名、存在しないものは Names に追加した上で出力する
class NameFilter < ValueFilter
  def initialize(path)
    require "names"
    @names = Names.new path
  end

  def close()
    @names.save :clean => true
  end

  def process(value, options)
    values = @names.get_standard_names value
    unless values
      @names.add value
      return value
    end

    return nil if values.empty?
    return values
  end
end


# 正規表現で指定された文字列を削除する
class RemoveFilter < ValueFilter
  # words は正規表現の配列
  def initialize(words)
    @words = Array(words)
  end

  def process(value, options)
    for word in @words
      value = value.gsub word, ""
    end
    value
  end
end

# 指定された文字列を別の文字列に置き換える
class GsubFilter < ValueFilter
  def initialize(pattern, replace)
    @pattern = pattern
    @replace = replace
  end

  def process(value, options)
    value.gsub @pattern, @replace
  end
end

# [0-9]~[0-9] のようなものを処理する
# 処理結果は {:min, :max} となる
# 数値が1つしか入っていない場合は :max に設定する
# 数値が不明な場合は :min, :max は nil
# 数値がアバウトな場合は、:min, :max の末尾に 「?」をつける
class NumberFilter < ValueFilter
  def process(value, options)
    result = {:min => nil, :max => nil}
    old = value
    value = value.gsub(/[-\/]/, "~").gsub("、", "")
    
    # アバウトな感じ?
    original = value
    ["↓", "前後", "約", "推定", /\?/, /くらい/, /^~/, "以下", "以上", "程度", "保護+HS=", "高い", "不明"].
      each {|a| value = value.gsub a, ""}
    about = value != original

    case value
    when "", "~"
      # 不明
    when /^([0-9]*)~([0-9]*)$/
      result[:min], result[:max] = $1, $2
    when /^([0-9]+)$/
      result[:max] = $1
    else
      raise "解析失敗 #{old}" unless about # about の場合は、「不明」とする
    end

    result[:max] = result[:min] if result[:min] && !result[:max]
    result[:min] += "?" if result[:min] && about
    result[:max] += "?" if result[:max] && about
    return result
  end
end

# 指定された Mob をスキップする
class SkipMobsFilter < Filter
  def initialize(skip_mobs)
    @skip_mobs = skip_mobs
  end
  
  def process(object)
    if @skip_mobs.include? object[:name]
      $stderr.puts "skip #{object[:name]}"
      raise Skip
    end
    object
  end
end

# NumberFilter の結果を max のみに変換する
# 不明な場合は UNKNOWN
class MaxFilter < ValueFilter
  def process(value, options)
    raise "value" unless value
    value[:max] || UNKNOWN
  end
end

# NumberFilter の結果をそれぞれのカラムに格納する
class MinMaxFilter < ValueFilter
  def initialize(min_column, max_column)
    @min_column = min_column
    @max_column = max_column
  end
  def process(value, options)
    options[:object][@min_column] = value[:min] || UNKNOWN
    options[:object][@max_column] = value[:max] || UNKNOWN
  end
end

# 経験値を処理する 例: 200(+32)
class ExpFilter < ValueFilter
  def initialize()
  end
  
  def process(value, options)
    old = value
    value = value.gsub("、", "").gsub(" ", "")
    case value
    when /^([0-9.]+)\(?\+\(?([0-9.]+)\)?$/
      options[:object][:party_exp] = Float($2)
      Float($1)
    when /^([0-9.]+)$/
      options[:object][:party_exp] = UNKNOWN
      Float($1)
    when /[\?]*/
      options[:object][:party_exp] = UNKNOWN
      UNKNOWN
    else
      raise "Exp 解析失敗 #{old}"
    end
  end
end

# ベース/サンライト/マナハーブ みたいなのを展開する
class ExpandFilter < ValueFilter
  # pattern は「(prefix)(展開部)(suffix)」の形になっている必要がある
  # 展開部は / で分解され、それぞれの前後に prefix, suffix が負荷される
  def initialize(pattern)
    @pattern = pattern
  end
  
  def process(value, options)
    raise "value" unless value
    if value =~ @pattern
      prefix = $1
      suffix = $3
      values = $2.split("/")
      if values.size >= 2
        return values.map {|a| prefix + a + suffix}
      end
    end
    value
  end
end

# Mob 情報を加工する
class MobFilter < ListFilter
  def initialize(options)
    super()

    names_dir = Pathname.new("names")
    
    split = SplitFilter.new
    split_space = SplitFilter.new(/[、,，\s・\/]\s*/) # スペースでも分割する
    split_items = SplitFilter.new(/[、,，\n・]\s*/) # アイテムは / で分割しない
    number = NumberFilter.new
    max = MaxFilter.new
    exp = ExpFilter.new

    builder = FilterBuilder.new(self)
    builder.
      filter(SkipMobsFilter.new(options[:skip_mobs])).
      all_columns(BasicFilter.new)

    # ReplaceFilter
    [
     :fields,
     :dungeons,
     :items,
    ].each do |column|
      builder.column column, ReplaceFilter.new(names_dir + "#{column}_replace.csv")
    end
    
    builder.
      column(:name,
             # たまに入ってる英語名称を削除
             [gsub(/\([a-zA-Z ]+\)$/, "")]).
      
      column(:fields, [split_space,
                       expand(/(.*?\()(.*)(\))/),
                      ]).
      column(:dungeons, [split,
                         expand(/(.*?\()(.*)(\))/),
                        ]).
      column(:life, [number, max]).
      column(:attack, [number, min_max(:attack_min, :attack_max)]).
      column(:gold, [remove(/[gｇＧ]/i), number, max]).
      column(:defensive, [number, max]).
      column(:protective, [number, max]).
      column(:skills, [split_space]).
      column(:exp, [exp]).
      
      column(:items, [split_items,
                      expand(/(['`])(.*)(['`]音の空き瓶.*)/),
                      expand(/(ファーストエイド)(.*)()/),
                      expand(/(.*ポーション)(.*)()/),
                      expand(/()(.*)(ポーション.*)/),
                      expand(/()(.*)(エレメンタル)$/),
                      expand(/()(.*)(ハーブ)$/),
                      expand(/^(小さ[いな])(.*)(の玉)$/),
                      expand(/(.*\()(♂\/♀)(\).*)/),
                      expand(/(.*\()(男性用\/女性用)(\).*)/),
                      expand(/()(.*)(革)$/),
                      expand(/()(.*)(鉱)$/),
                      expand(/()(.*)(板)$/),
                      expand(/(.*?)([0-9\/]+)(ページ)$/),
                      expand(/(.*)(爪\/毛)()$/),
                      expand(/()(.*?)(インゴット.*)/),
                     ]).
      column(:titles, []).
      column(:sketch_exp, [])
    
    # NameFilter

    names_list = [
                   :fields,
                   :dungeons,
                   :is_1for1,
                   :num_of_attacks,
                   :search_range,
                   :move_speed,
                   :is_first_attack,
                   :search_speed,
                   :skills,
                   :items,
                   :elemental
                  ]
    
    names_list.each do |column|
      builder.column column, NameFilter.new(names_dir + "#{column}.csv")
    end
    
  end

  private
  def gsub(pattern, replace) GsubFilter.new(pattern, replace) end
  def remove(pattern) RemoveFilter.new(pattern) end
  def min_max(min_column, max_column) MinMaxFilter.new(min_column, max_column) end
  def expand(pattern) ExpandFilter.new(pattern) end

end
