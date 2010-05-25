#!/usr/local/bin/ruby -Ku
# -*- coding: utf-8 -*-
#
# CSV から mob データを読み込んで正規化する
#
# 
#
# TODO
# - 氷の魔女
# - 音の空き瓶
# - 赤/青のたま系
# - エンチャントのフォーマット統一
# - 数値に MR:2560 とか入ってる
# - $skip_mobs してる子

require "jcode"
require "pathname"

# ----------------------------------------------------------------------
# 設定

# 名称リストから未使用の名称を削除するなら true
$clean_names = false

# 読み込む CSV
$source_path = Pathname.new("mobs") + "すべて.csv"

# 結果保存 CSV
$result_path = Pathname.new("mobs") + "tmp.csv"

UNKNOWN = "★不明"

# 基本的に1つの mob 欄に複数の値が入っているものは解析失敗する
$skip_mobs = ["ゴースト", "サルファーゴーレム", "スモールゴーレム(初級)", "スモールゴーレム", 
              "スモールゴーレム(強化)"]

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

# ----------------------------------------------------------------------
# フィルタ

require "filter"

# 基本的な正規化を行う
# - 記号と英数字を全角 => 半角
# - 前後のスペースを削除
class BasicFilter < ValueFilter
  def process(column, value)
    value.tr("（）？　／", "()? /").gsub("??", "?").gsub("(?)", "?").strip
  end
end

# あいう(A, B, C) を あいう(A), あいう(B), あいう(C) というリストに変換する
# この処理を行う前に SplitFilter していること
class ParenthesesFilter < ValueFilter
  def initialize()
  end

  def process(column, value)
    # カッコの中身を抜き出す
    if /(.+?)\((.+?)\)/ =~ value
      prefix = $1
      list = $2.split(",")
      if !list.empty?
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
  
  def process(column, value)
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
class NameFilter < ValueFilter
  def initialize(names)
    raise "names" unless names
    @names = names
  end

  def process(column, value)
    name = @names.get_standard_name value
    return name if name
    @names.add value
    return value
  end
end

# 正規表現で指定された文字列を削除する
class RemoveFilter
  # words は正規表現の配列
  def initialize(words)
    @words = Array(words)
  end

  def process(column, value)
    for word in @words
      value = value.gsub word, ""
    end
    value
  end
end

# 指定された文字列を別の文字列に置き換える
class GsubFilter
  def initialize(pattern, replace)
    @pattern = pattern
    @replace = replace
  end

  def process(column, value)
    value.gsub @pattern, @replace
  end
end

class Exp < ValueFilter
end

class NumberFilter < ValueFilter
  def process(column, value)
    old = value
    value = value.gsub(/[-～〜\/]/, "~").gsub("、", "")
    
    # アバウトな感じ?
    original = value
    ["↓", "前後", "約", "推定", /\?/, /くらい/, /^~/, "以下", "以上", "程度", "保護+HS=", "高い"].
      each {|a| value = value.gsub a, ""}
    
    about = value != original

    if ["", "~"].any? {|a| a == value}
      value = UNKNOWN
    else
      if value =~ /^[0-9\.\~]+$/
        value += "?" if about
      else
        if about
          value = UNKNOWN
        else
          raise "解析失敗 #{old}"
        end
      end
    end
    
    "#{old} => #{value}"
  end
end

class Attack < ValueFilter
end

class Gold < ValueFilter
end

class SkipMobsFilter
  def process(object)
    if $skip_mobs.include? object[:name]
      $stderr.puts "skip #{object[:name]}"
      raise Skip
    end
    object
  end
end

split = SplitFilter.new
split_space = SplitFilter.new(/[、,，\s・\/]\s*/) # スペースでも名前を分割する
paren = ParenthesesFilter.new
clean = RemoveFilter.new [/^期間：.*/]
number = NumberFilter.new

def names(column) NameFilter.new($names_hash[column]) end
def gsub(pattern, replace) GsubFilter.new(pattern, replace) end

$mob_filter = FilterBuilder.new.
  filter(SkipMobsFilter.new).
  all_columns(BasicFilter.new).
  
  column(:name,
         # たまに入ってる英語名称を削除
         [gsub(/\([a-zA-Z ]+\)$/, "")]).
  
  column(:fields, [clean, split_space, paren, names(:fields)]).
  column(:dungeons, [clean, split, paren, names(:dungeons)]).
  column(:life, [number]).
  column(:attack, [number]).
  column(:gold, []).
  column(:is_1for1, [names(:is_1for1)]).
  column(:defensive, [number]).
  column(:num_of_attacks, [names(:num_of_attacks)]).
  column(:search_range, [names(:search_range)]).
  column(:protective, [number]).
  column(:move_speed, [names(:move_speed)]).
  column(:is_first_attack, [names(:is_first_attack)]).
  column(:search_speed, [names(:search_speed)]).
  column(:skills, [split_space, names(:skills)]).
  column(:exp, []).

  # エンチャなどがあるので paren はすべきじゃない
  column(:items, [gsub(/['`"](.+?)['`"]音の空き瓶/, '音の空き瓶(\1)'),
                  split, names(:items)]).
  column(:elemental, [names(:elemental)]).
  column(:tactics, []).
  column(:information, []).
  column(:titles, []).
  column(:sketch_exp, []).
  result

# ----------------------------------------------------------------------
# CSV

# カラム名の配列(CSV の順に並んでいる)
$columns = [
            :family,
            :name,
            :fields,
            :dungeons,
            :life,
            :attack,
            :gold,
            :is_1for1,
            :defensive,
            :num_of_attacks,
            :search_range,
            :protective,
            :move_speed,
            :is_first_attack,
            :search_speed,
            :skills,
            :exp,
            :items,
            :elemental,
            :tactics,
            :information,
            :titles,
            :sketch_exp
           ]

# ----------------------------------------------------------------------
# 実行！

class Logger
  def initialize(columns)
    @columns = Array(columns)
  end
  def process(object)
    puts @columns.map{|c|object[c]}.join(", ")
    object
  end
end

require "my_csv"
input = CsvReader.new $source_path, $columns
output = CsvWriter.new $result_path, $columns, $columns

filters = ListFilter.new [input, Logger.new([:name]), $mob_filter, Logger.new([:dungeons]), output]

while true
  begin
    object = filters.process(nil)
    break unless object
  rescue Skip
  end
end

# 名称リストを更新する
$names_hash.values.each {|a|a.save(:clean => $clean_names)}
