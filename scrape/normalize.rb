#!/usr/local/bin/ruby -Ku
# -*- coding: utf-8 -*-
#
# CSV から mob データを読み込んで正規化する
#
# 
#

require "jcode"
require "pathname"

# ----------------------------------------------------------------------
# 設定

# 名称リストから未使用の名称を削除するなら true
$clean_names = true

# 読み込む CSV
$source_path = Pathname.new("mobs") + "すべて.csv"

# 結果保存 CSV
$result_path = Pathname.new("mobs") + "tmp.csv"

UNKNOWN = "★不明"

# 基本的に1つの mob 欄に複数の値が入っているものは解析失敗する
$skip_mobs = ["ゴースト", "サルファーゴーレム", "スモールゴーレム(初級)", "スモールゴーレム", 
              "スモールゴーレム(強化)"]

$debug = true

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
  def process(value, options)
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
class NameFilter < ValueFilter
  def initialize(names)
    raise "names" unless names
    @names = names
  end

  def process(value, options)
    raise "value" unless value
    names = @names.get_standard_names value
    unless names
      @names.add value
      return value
    end

    return nil if names.empty?
    return names
  end
end

# 正規表現で指定された文字列を削除する
class RemoveFilter
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
class GsubFilter
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

class SkipMobsFilter
  def process(object)
    if $skip_mobs.include? object[:name]
      $stderr.puts "skip #{object[:name]}"
      raise Skip
    end
    object
  end
end

# NumberFilter の結果を max のみに変換する
# 不明な場合は UNKNOWN
class MaxFilter
  def process(value, options)
    raise "value" unless value
    value[:max] || UNKNOWN
  end
end

# NumberFilter の結果をそれぞれのカラムに格納する
class MinMaxFilter
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
class Exp < ValueFilter
  def initialize(source_column)
  end
  
  def process(value, options)
  end
end

# ベース/サンライト/マナハーブ みたいなのを分解する
class SuffixFilter
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

split = SplitFilter.new
split_space = SplitFilter.new(/[、,，\s・\/]\s*/) # スペースでも名前を分割する
split_items = SplitFilter.new(/[、,，\n・]\s*/)
paren = ParenthesesFilter.new
number = NumberFilter.new
herb = SuffixFilter.new("ハーブ")
elemental = SuffixFilter.new("エレメンタル")
max = MaxFilter.new

def names(column) NameFilter.new($names_hash[column]) end
def gsub(pattern, replace) GsubFilter.new(pattern, replace) end
def remove(pattern) RemoveFilter.new(pattern) end
def min_max(min_column, max_column) MinMaxFilter.new(min_column, max_column) end

$mob_filter = FilterBuilder.new.
  filter(SkipMobsFilter.new).
  all_columns(BasicFilter.new).
  
  column(:name,
         # たまに入ってる英語名称を削除
         [gsub(/\([a-zA-Z ]+\)$/, "")]).
  
  column(:fields, [remove(/^期間：.*/), split_space, paren, names(:fields)]).
  column(:dungeons, [remove(/^期間：.*/), split, paren, names(:dungeons)]).
  column(:life, [number, max]).
  column(:attack, [number, min_max(:attack_min, :attack_max)]).
  column(:gold, [remove(/g/i), number, max]).
  column(:is_1for1, [names(:is_1for1)]).
  column(:defensive, [number, max]).
  column(:num_of_attacks, [names(:num_of_attacks)]).
  column(:search_range, [names(:search_range)]).
  column(:protective, [number, max]).
  column(:move_speed, [names(:move_speed)]).
  column(:is_first_attack, [names(:is_first_attack)]).
  column(:search_speed, [names(:search_speed)]).
  column(:skills, [split_space, names(:skills)]).
  column(:exp, []).

  # エンチャなどがあるので paren はすべきじゃない
  column(:items, [gsub(/['`"](.+?)['`"]音の空き瓶/, '音の空き瓶(\1)'),
                  split_items, herb, elemental, names(:items)]).
  column(:elemental, [names(:elemental)]).
  column(:tactics, []).
  column(:information, []).
  column(:titles, []).
  column(:sketch_exp, []).
  result

# ----------------------------------------------------------------------
# CSV

# カラム名の配列(CSV の順に並んでいる)
$input_columns = [
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

$output_columns = [
                   :family,
                   :name,
                   :fields,
                   :dungeons,
                   :life,
                   :attack_min,
                   :attack_max,
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
# デバッグ

# 各カラムの編集前の値を複製して保存しておく(比較用)
class BackupFilter
  def process(object)
    result = {}
    for key, value in object
      result[key] = value
      result[:"#{key}(加工前)"] = value
    end
    result
  end
end

class Logger
  def initialize(columns)
    @columns = Array(columns)
  end
  def process(object)
    puts @columns.map{|c|object[c]}.join(", ")
    object
  end
end

# ----------------------------------------------------------------------
# 実行！

# デバッグ用に加工前データも出力する
if $debug
  tmp = []
  for column in $output_columns
    case column
    when :attack_max
      # 無視
    when :name, :family
      # 加工しないので加工前はいらない
      tmp << column
    when :attack_min
      tmp << :"attack(加工前)"
      tmp << :attack_min
      tmp << :attack_max
    else
      tmp << :"#{column}(加工前)"
      tmp << column
    end
  end
  $output_columns = tmp
end

require "my_csv"
input = CsvReader.new $source_path, $input_columns
output = CsvWriter.new $result_path, $output_columns, $output_columns

filters = ListFilter.new [input, BackupFilter.new, Logger.new([:name]), $mob_filter, Logger.new([:dungeons]), output]

while true
  begin
    object = filters.process(nil)
    break unless object
  rescue Skip
  end
end

# 名称リストを更新する
$names_hash.values.each {|a|a.save(:clean => $clean_names)}
