#!/usr/local/bin/ruby -Ku
# -*- coding: utf-8 -*-
#
# CSV から mob データを読み込んで正規化する
#
# 
#

require "jcode"
require "pathname"
require "filter"
require "mob_filter"
require "my_csv"

# ----------------------------------------------------------------------
# 設定

$debug = true

# 入力データのカラム名の配列
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

# 出力データのカラム名の配列
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
                   :party_exp,
                   :items,
                   :elemental,
                   :tactics,
                   :information,
                   :titles,
                   :sketch_exp
                  ]

# デバッグ用に加工前データも出力する
if $debug
  tmp = []
  for column in $output_columns
    case column
    when :name, :family, :party_exp, :attack_max
      # 加工しないので加工前はいらない
      tmp << column
    when :attack_max
      # 無視
    when :attack_min
      tmp << :"attack(加工前)"
      tmp << :attack_min
    else
      tmp << :"#{column}(加工前)"
      tmp << column
    end
  end
  $output_columns = tmp
end

# 名称リストから未使用の名称を削除するなら true
$clean_names = false

# スキップする mob 名
# 基本的に1つの mob 欄に複数の値が入っているものは解析失敗する
$skip_mobs = ["ゴースト", "サルファーゴーレム", "スモールゴーレム(初級)", "スモールゴーレム", 
              "スモールゴーレム(強化)", "巨大赤クモ", "巨大黒クモ", "巨大白クモ"]

$input_dir = Pathname.new("mobs")

# 入力ファイル名
$input_files = [
                "影世界.csv",
                "節足動物ＭＯＢＤＢ 1_1Tf.csv",
                "鳥類ＭＯＢＤＢ 1_1Tf.csv",
                "アンデッド.csv",
                "ストーン系.csv",
                "ボスモンスター.csv",
                "亜人種.csv",
                "哺乳類.csv",
                "悪魔族.csv",
                "爬虫類.csv",
                "魔法生命体.csv"
               ]

# 入力
$input = ConcatFilter.new($input_files.map {|a| CsvReader.new($input_dir + a, $input_columns)})

# 出力
$output = CsvWriter.new $input_dir + "tmp2.csv", $output_columns, $output_columns

# ----------------------------------------------------------------------
# デバッグ

# 各カラムの編集前の値を複製して保存しておく(比較用)
class BackupFilter < Filter
  def process(object)
    result = {}
    for key, value in object
      result[key] = value
      result[:"#{key}(加工前)"] = value
    end
    result
  end
end

class Logger < Filter
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

filters = ListFilter.new [$input,
                          BackupFilter.new,
                          Logger.new([:name]),
                          MobFilter.new(:skip_mobs => $skip_mobs),
                          Logger.new([:dungeons]),
                          $output]

FilterRunner.new.run filters

# 名称リストを更新する
$names_hash.values.each {|a|a.save(:clean => $clean_names)}
