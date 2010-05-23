# -*- coding: utf-8 -*-

# Mabinogi Wiki HTML 解析用の雑多なユーティリティ

# 指定された HTML を Nokogiri 形式で取得する
# キャッシュがあるならキャッシュを使用する
def get_html(url)
  require "pathname"
  require "nokogiri"
  cache = Pathname.new("cache") + url.gsub(/[:\/]/, ".")
  if cache.exist?
    # puts 'use cache'
  else
    require 'mechanize'
    agent = Mechanize.new
    open(cache, "w") do |f|
      f.write agent.get(url).root.to_html
    end
  end

  doc = open(cache) do |f|
    Nokogiri::HTML(f)
  end
end

# HTML 内の範囲を表す
class Region
  attr_reader :first, :last
  
  # (first...last)
  def initialize(first, last = nil)
    @first = first
    @last = last || next_(first)
  end
  
  def search_next(element, selector)
    element = next_ element
    while element and (element <=> @last) < 0
      return element if element.matches? selector
      child = element.at selector
      return child if child
      element = element.next
    end

    if (element <=> @last) < 0
      return nil
    end

    # return search_next(element.parent, selector)
  end

  private
  def next_(element)
    return element.next if element.next
    return next_ element.parent
  end
end

# ページの1セクション
# last は nil の場合がある
class Section < Region
  attr_reader :first, :last, :children
  attr_accessor :parent
  def initialize(first, last, children)
    super(first, last)
    @children = children

    @children.each do |c|
      c.parent = self
    end
  end
  
end

# first から first と同階層の Section を処理する
# 処理した要素は headings から取り除く
def split_page_(headings)
  raise "headings" if !headings || headings.empty?

  sections = []
  children = []
  first = headings.shift
  while true
    cur = headings.first
    finish = !cur || first.node_name > cur.node_name
    if finish || first.node_name == cur.node_name
      sections << Section.new(first, cur, children)
      break if finish
      first = cur
      children = []
      headings.shift
    elsif first.node_name < cur.node_name
      children = split_page_(headings)
    end
  end

  return sections
end

# ページ全体を大まかなブロックに分割する
# 戻り値は Section の Array
# # h2 のリスト
# [
#   [h2_first,
#   [[h3_first, []]# h3 の開始要素
#    ],
# ]
def split_page(html)
  headings = html.search("#body h2, #body h3, #body h4").sort
  result = split_page_(headings)
  
  # result.each do |h2|
  #   puts h2.first.node_name + ", " +  h2.first.content
  #   h2.children.each do |h3|
  #     puts " " + h3.first.node_name + ", " + h3.first.content
  #     h3.children.each do |h4|
  #       puts " " + h4.first.node_name + ", " + h4.first.content
  #     end
  #   end
  # end
end


# テーブルを解析してハッシュにして返す
# 
# アルゴリズム
# - 基本は th とその直後の td がペアになると考える
# - th が連続した場合は、 その後に td が連続していると考える
def parse_table(table)
  raise "table" unless table.is_a? Nokogiri::XML::Node

  result = {}
  ths = [] # th が連続した場合は、 その後に td が連続していると考える
  table.search("th, td").sort.each do |e|
    if e.node_name == "th"
      ths << e
    elsif e.node_name == "td"
      if !ths.empty?
        th = ths.shift
        result[to_text(th)] = to_text(e)
      end
    end
  end
  result
end

# 指定された要素からタグなどを取り除く
def to_text(node)
  
  br = Nokogiri::XML::Text.new("\n", node.document)
  node.search("br").each {|e|e.replace(br)}
  
  return node.content.strip
end
