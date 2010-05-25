# -*- coding: utf-8 -*-

# 複数の名前を扱う
# 名前から正式名称を取得することができる
#
# = ファイルフォーマット
# - CSV。 第1カラムが正式名称、それ以降のカラムは正式ではない名前
# - 正式名称が <delete> の場合、その名称は未使用
# - 正式名称が複数ある場合、 「|」で区切る
class Names
  
  def initialize(path)
    $stderr.puts path
    @path = path
    @name_hash = {} # 名称 => 正式名称 ハッシュ
    @used_names = {} # 使用された名称 => true

    return unless @path.exist?
    
    require "csv"
    CSV.open(path, 'r') do |row|
      next if row.empty? || row[0].to_s.empty?
      standard = row[0]
      for name in row
        @name_hash[name] = standard
      end
    end
  end

  # 正式名称を取得する
  # 存在しない場合は nil
  # name が使用されていない場合はからのリスト
  def get_standard_names(name)
    @used_names[name] = true
    names = @name_hash[name]
    return nil unless names
    return [] if names == "<delete>"
    names.split("|")
  end

  def add(name)
    raise "name" unless name
    puts "add: #{name}"
    @name_hash[name] = name
  end

  # ファイルに書き出す
  # 未使用の名称を削除する場合は :clean => true
  def save(options = {})
    options = {:clean => false}.merge(options)
    
    @path.rename(@path.to_s + ".old") if @path.exist?

    # 正式名 => [名前, ...]
    names = Hash.new {|h,k| h[k] = []}
    for name, standard_name in @name_hash
      names[standard_name] << name if !options[:clean] || @used_names[name]
    end
    names = names.sort
    
    require "csv"
    CSV.open(@path, 'w') do |csv|
      for standard_name, sub_names in names
        csv << ([standard_name] + sub_names.sort).uniq
      end
    end
  end
end

# ----------------------------------------------------------------------
if $0 == __FILE__
end
