# -*- coding: utf-8 -*-
# CSV を読み込んでハッシュとして返す
class CsvReader
  def initialize(path, columns)
    @columns = columns
    require "csv"
    require "kconv"
    open(path, 'r') do |file|
      @reader = CSV::Reader.create file.read.toutf8
    end
    @reader.shift # ヘッダー
  end

  def close()
    @reader.close
  end
  
  # 1件読み込む
  def process(dummy)
    result = {}
    row = @reader.shift
    return nil if row.size <= 1

    @columns.each_with_index do |column, i|
      result[column] = row[i]
    end
    
    result
  end
end

# ハッシュのリストを CSV へ書き出す
class CsvWriter
  def initialize(path, header, columns)
    @columns = columns
    require "csv"
    require "kconv"
    @writer = CSV.open(path, 'w')
    @writer << header.map {|a| a.to_s}
  end

  def close()
    @writer.close
  end
  
  # 1件書き込む
  def process(object)
    @writer << @columns.map{|c| Array(object[c]).join("\n")}
    object
  end
end
