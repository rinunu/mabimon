# -*- coding: utf-8 -*-

require "filter"

UNKNOWN = "★不明"

# ----------------------------------------------------------------------
# 名称リスト
#
# $names_dir にある「名称リスト.csv」に名前情報を持っているものたち

require "names"

$names_dir = Pathname.new("names")

$names_list = [
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

$names_hash = {}
$names_list.each {|n| $names_hash[n] = Names.new($names_dir + "#{n}.csv")}

# split

# ----------------------------------------------------------------------
# フィルタ

# 基本的な正規化を行う
# - 記号と英数字を全角 => 半角
# - 前後のスペースを削除
class BasicFilter < ValueFilter
  def process(value, options)
    raise "value: #{options[:column]}" unless value
    value.tr("（）？　／－", "()? /ー").gsub("??", "?").
      gsub(/[～〜]/, "~").
      gsub("(?)", "?").strip
  end
end

# あいう(A, B, C) を あいう(A), あいう(B), あいう(C) というリストに変換する
# この処理を行う前に SplitFilter していること
class ParenthesesFilter < ValueFilter
  def initialize()
  end

  def process(value, options)
    # カッコの中身を抜き出す
    if /(.+?)\((.+?)\)/ =~ value
      prefix = $1
      list = $2.split(",")
      if list.size >= 2
        return list.map{|a| prefix + a}
      end
    end
    value
  end
end

# あ,い,う を 「あ」「い」「う」に分解し、リストに変換する
# ただし () でくくられているものは分解しない
# また、区切り文字を正規化し、 「,」のみにする
class SplitFilter < ValueFilter
  def initialize(separator = /[、,，\n・\/]\s*/)
    @separator = separator
  end
  
  def process(value, options)
    # もっと素直にできないかな。。
    
    # すべての区切りを <sep> にする
    value = value.gsub(@separator, "<sep>")
    # () に囲まれた 「<sep>」 は「,」に戻す
    value = value.gsub(/<sep>(?=[^()]*\))/, ',')
    value.split("<sep>")
  end
end

# 名前を統一するためのフィルタ
# Names に存在するものはその正式名、存在しないものは Names に追加した上で出力する
# Names がない場合は何もしない
class NameFilter < ValueFilter
  def initialize(names_hash)
    raise "names_hash" unless names_hash.is_a? Hash
    @names_hash = names_hash
  end

  def process(value, options)
    names = @names_hash[options[:column]]
    return value unless names
    
    values = names.get_standard_names value
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

# ベース/サンライト/マナハーブ みたいなのを分解する
class SuffixFilter < ValueFilter
  def initialize(suffix)
    @suffix = suffix
  end
  
  def process(value, options)
    raise "value" unless value
    if value =~ /^(.*)#@suffix$/
      value.split("/").map do |a|
        if a.include? @suffix
          a
        else
          a + @suffix
        end
      end
    else
      value
    end
  end  
end

class MobFilter < ListFilter
  def initialize(options)
    super()
    
    split = SplitFilter.new
    split_space = SplitFilter.new(/[、,，\s・\/]\s*/) # スペースでも名前を分割する
    split_items = SplitFilter.new(/[、,，\n・]\s*/)
    paren = ParenthesesFilter.new
    number = NumberFilter.new
    herb = SuffixFilter.new("ハーブ")
    elemental = SuffixFilter.new("エレメンタル")
    max = MaxFilter.new
    exp = ExpFilter.new
    
    FilterBuilder.new(self).
      filter(SkipMobsFilter.new(options[:skip_mobs])).
      all_columns(BasicFilter.new).
      
      column(:name,
             # たまに入ってる英語名称を削除
             [gsub(/\([a-zA-Z ]+\)$/, "")]).
      
      column(:fields, [remove(/^期間：.*/), split_space, paren]).
      column(:dungeons, [remove(/^期間：.*/), split, paren]).
      column(:life, [number, max]).
      column(:attack, [number, min_max(:attack_min, :attack_max)]).
      column(:gold, [remove(/[gｇＧ]/i), number, max]).
      column(:is_1for1, []).
      column(:defensive, [number, max]).
      column(:num_of_attacks, []).
      column(:search_range, []).
      column(:protective, [number, max]).
      column(:move_speed, []).
      column(:is_first_attack, []).
      column(:search_speed, []).
      column(:skills, [split_space]).
      column(:exp, [exp]).
      
      # エンチャなどがあるので paren はすべきじゃない
      column(:items, [gsub(/['`"](.+?)['`"]音の空き瓶/, '音の空き瓶(\1)'),
                      split_items, herb, elemental]).
      column(:elemental, []).
      column(:tactics, []).
      column(:information, []).
      column(:titles, []).
      column(:sketch_exp, []).
      
      all_columns(NameFilter.new($names_hash))
  end

  private
  def gsub(pattern, replace) GsubFilter.new(pattern, replace) end
  def remove(pattern) RemoveFilter.new(pattern) end
  def min_max(min_column, max_column) MinMaxFilter.new(min_column, max_column) end

end
