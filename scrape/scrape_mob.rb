#!/usr/local/bin/ruby -Ku
# -*- coding: utf-8 -*-
#
# = セットアップ
# RubyGems, Mechanize, Nokogiri が必要
#
# = 使用方法
# 以下の設定を行った後、コマンドラインで
#
# $ ruby scrape_mob.rb
#
# 保存済みの CSV は再度処理しないため、再処理したい場合は削除すること。
# 一度取得した HTML はキャッシュするため、再度取得したい場合はキャッシュを削除すること。
# 
# = TODO
# - 丸数字とかが化ける
# - 影世界やボスモンスターを処理出来ない
# 

require "rubygems"
require "pathname"
require "utility"
require "kconv"

# ----------------------------------------------------------------------
# 設定

# スキップする MOB
$skip_categories = ["影世界"]
$skip_families = ["イリアの巨大フィールドボス", "メインストリームボス"]
$skip_mobs = ["スケルトン(初心者修練用)"]

root = "http://mabinogi.wikiwiki.jp/index.php?%A5%E2%A5%F3%A5%B9%A5%BF%A1%BC%2F%A5%C7%A1%BC%A5%BF%A5%D9%A1%BC%A5%B9"

$page = nil

# すべての Mob を処理する場合はここを削除する
# $page = {
#   :family => "蛾",
#   :url => "http://mabinogi.wikiwiki.jp/index.php?%A5%E2%A5%F3%A5%B9%A5%BF%A1%BC%2F%A5%C7%A1%BC%A5%BF%A5%D9%A1%BC%A5%B9%2F%B2%EB"
# }

# ----------------------------------------------------------------------
# モンスターページ依存 util

# モンスター名っぽいなら true
def mob_name?(name)
  not_mob = ["特徴", "【", "データベース", "コメント", "一般", "攻略", "知識"]
  not not_mob.any? {|a| name.include? a}
end

# ----------------------------------------------------------------------
# MOB 目次

# 「Top > モンスター > データベース」 ページを解析し、解析結果を返す
# 結果は [{:category => カテゴリ, :family => 種族, :url => url}, ...]
def parse_index(page)
  # カテゴリ一覧
  heads = page.search("#body h2, #body h3").sort.reverse
  heads.pop # 「目次」を取り除く
  
  list = []
  page.search("#body li>a").each do |a|
    head = heads.find {|h| (h <=> a) < 0}
    if head
      list << {:category => to_text(head), :family => to_text(a), :url => a["href"]}
    end
  end
  list
end

# ----------------------------------------------------------------------
# MOB ページ

# ソースから Mob 情報の1カラムを取り出す
class ColumnParser
end

# ColumnParser のデフォルトの実装
class DefaultColumnParser
  attr_reader :key
  def initialize(key, label, options = {})
    @options = {:required => true}.merge(options)
    @key = key
    if label.is_a? Array
      @labels = label
    else
      @labels = [label]
    end
  end

  def parse(hash)
    value = nil
    keys = get_keys hash

    # 複数のフィールドをもつ場合があるため、合成する
    value = nil
    if keys.empty?
    elsif keys.size == 1
      value = hash[keys[0]]
    else
      $stderr.puts "複数存在します: " + @key.to_s
      value = ""
      for key in keys
        value += "[%s]\n%s" % [key, hash[key]]
      end
    end

    unless value
      msg = "未指定: " + @key.to_s
      raise msg if @options[:required]
      $stderr.puts msg
      return "★未指定?"
    end
    value
  end

  def get_keys(hash)
    keys = hash.keys.find_all {|k| @labels.any? {|l| l === k}}
  end

end

# 値がリストになっているカラム用の ColumnParser
class ListColumnParser < DefaultColumnParser
  def initialize(key, label, options = {})
    super(key, label, options)
  end

  def parse(hash)
    # todo value が複数の場合, からの場合
    value = super
    value = value.split(/[,、\n]/).map {|s| s.strip}
  end
end

$column_parsers = [
                   ListColumnParser.new(:fields, "フィールド",
                                           :required => false),
                   ListColumnParser.new(:dungeons, "ダンジョン",
                                           :required => false),
                   DefaultColumnParser.new(:life, "生命力"),
                   DefaultColumnParser.new(:attack, ["攻撃力", "攻撃"]),
                   DefaultColumnParser.new(:gold, "金貨"),
                   DefaultColumnParser.new(:is_1for1, ["1:1属性", "1:1属性?"]),
                   DefaultColumnParser.new(:defensive, "防御力"),
                   DefaultColumnParser.new(:num_of_attacks, "攻撃打数"),
                   DefaultColumnParser.new(:search_range, "索敵"),
                   DefaultColumnParser.new(:protective, "保護"),
                   DefaultColumnParser.new(:move_speed, "移動速度"),
                   DefaultColumnParser.new(:is_first_attack, "先/後"),
                   DefaultColumnParser.new(:search_speed, "認識速度",
                                           :required => false),
                   ListColumnParser.new(:skills, "スキル"),
                   DefaultColumnParser.new(:exp, "経験値"),
                   ListColumnParser.new(:items, /ドロップアイテム/,
                                        :required => false),
                   DefaultColumnParser.new(:elemental, "エレメンタル"),
                   DefaultColumnParser.new(:tactics, ["攻略", "攻略法"],
                                           :required => false),
                   DefaultColumnParser.new(:information, "情報"),
                   ListColumnParser.new(:titles, "タイトル",
                                           :required => false),
                   DefaultColumnParser.new(:sketch_exp, "スケッチによる探険経験値", 
                                           :required => false)
                  ]

# モンスター情報欄を解析し、 Mob を返す
# 解析対象がなかった場合は nil
def parse_mob(page, section)
  obj = {}
  obj[:name] = to_text(section.first)

  return nil if $skip_mobs.include? obj[:name]

  table = section.search_next(section.first, "table")
  return nil unless table
  
  hash = parse_table table

  return nil if hash["設置位置"] # 設置物は無視

  $stderr.puts "mob : " + obj[:name]
  
  obj[:family] = page[:family]

  for parser in $column_parsers
    value = parser.parse(hash)
    obj[parser.key] = value
  end

  return obj
end

def parse_mob_list_(page, sections)
  mobs = []

  sections.each do |section|
    if section.children.empty?
      next if !mob_name? section.first.content

      begin
        mob = parse_mob(page, section)
        unless mob
          $stderr.puts "mob " + page[:family] + ": データが存在しないためスキップします"
          next
        end
        
        mobs << mob
      end
    else
      mobs += parse_mob_list_(page, section.children)
    end
  end
  return mobs
end

# モンスターページを解析し、 Mob の配列を返す
# インデックスページの場合は nil を返す
def parse_mob_list(page, html)
  # インデックスページ?
  if html.search("#body table").empty?
    return nil
  else
    sections = split_page html
    parse_mob_list_(page, sections)
  end
end

# ----------------------------------------------------------------------
# CSV 化

# カラム名の配列(出力順に並んでいる)
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

$column_names = [
                 "種族",
                 "名称",
                 "フィールド",
                 "ダンジョン",
                 "生命力",
                 "攻撃力",
                 "金貨",
                 "1:1属性",
                 "防御力",
                 "攻撃打数",
                 "索敵",
                 "保護",
                 "移動速度",
                 "先/後",
                 "認識速度",
                 "スキル",
                 "経験値",
                 "ドロップアイテム",
                 "エレメンタル",
                 "攻略法",
                 "情報",
                 "タイトル1",
                 "タイトル2",
                 "タイトル3",
                 "タイトル4",
                 "スケッチによる探検経験値",
           ]

# CSV 用エスケープ
def escape_csv(s)
  '"' + s.to_s.gsub(/,/, "、").gsub(/"/, "'") + '"'
end

def header_to_csv
  $column_names.join(", ")
end

def mobs_to_csv(mobs)
  result = []
  for mob in mobs
    a = []
    for column in $columns
      value = mob[column]
      if column == :titles
        value = value[0..3]
        value.fill("", value.size..3) if value.size < 4
        a += value.map{|a| escape_csv a}
      else
        if value.is_a? Array
          value = value.join("\n")
        end
        a << escape_csv(value)
      end
    end
    result << a.join(",")
  end
  result.join("\n")
end

# ----------------------------------------------------------------------

# mob のリストのリストを CSV として保存する
def save_category_csv(path, mobs_list)
  open(path, "w") do |f|
    f.puts header_to_csv.tosjis
    for mobs in mobs_list
      f.puts mobs_to_csv(mobs).tosjis
    end
  end
end

# 目次情報をもとに、すべての Mob 情報を取得し、CSV として保存する。
# 結果は mobs/ ディレクトリに保存する
def save_all(index)
  raise "index" if !index || index.size == 0

  category = nil
  category_mobs = nil
  category_path = nil
  for page in index
    if category != page[:category]
      # 1回目のループで保存しないための if
      save_category_csv category_path, category_mobs if category_mobs

      category_path = Pathname.new("mobs") + (page[:category] + ".csv")
      category_mobs = []
      category = page[:category]
    end

    if category_path.exist?
      $stderr.puts "カテゴリ " + page[:category] + ": 処理済みのためスキップします"
      next
    end
    
    if $skip_categories.include? page[:category]
      $stderr.puts "カテゴリ " + page[:category] + ": 未対応のためスキップします"
      next
    end

    if $skip_families.include? page[:family]
      $stderr.puts "種族 " + page[:family] + ": 未対応のためスキップします"
      next
    end
    
    puts page[:family] + ": " + page[:url]
    mobs = parse_mob_list(page, get_html(page[:url]))
    unless mobs
      $stderr.puts "種族 " + page[:family] + ": スキップします"
      next
    end
    category_mobs << mobs
  end
  
  save_category_csv category_path, category_mobs
end

# ----------------------------------------------------------------------
# 実行！

unless $page
  # ----------
  # 全部ガッツリ処理する場合
  index = parse_index(get_html(root))
  save_all(index)
else

  # ----------
  # 1ファイルだけ処理する場合

  mobs = parse_mob_list($page, get_html($page[:url]))
  puts header_to_csv
  puts mobs_to_csv mobs
  
end
