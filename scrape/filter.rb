# -*- coding: utf-8 -*-

class Skip < Exception
end

# フィルター
#
# object を加工する
class Filter
  # object にフィルターを適用して返す
  # object 自体を変更して返す場合も、複製を返す場合もある
  # 処理するものがなかった場合は nil を返す
  # スキップする場合は raise Skip
  def process(object)
    object
  end
end

# 複数の Filter を適用する Filter
class ListFilter
  def initialize(filters = [])
    @filters = Array(filters)
  end

  def add(filter)
    @filters << filter
  end
  
  def process(object)
    for filter in @filters
      object = filter.process object
      break unless object
    end
    object
  end
end

# カラムに ValueFilter を適用する
# 継承して使用する
class ColumnFilter
  # columns に対象のカラムを指定する。 [] ならすべて。
  def initialize(filter, columns = [])
    raise "filter" unless filter
    
    @filter = filter
    @columns = Array(columns)
  end

  def process(object)
    columns = !@columns.empty? ? @columns : object.keys
    for column in columns
      process_column(object, column)
    end
    object
  end

  def process_column(object, column)
    options = {:object => object, :column => column}
    value = object[column]
    if value.is_a? Array
      result = []
      for v in value
        result += Array(@filter.process(v, options))
      end
      value = result
    else
      value = @filter.process(value, options)
    end

    value.compact if value.is_a? Array
    
    object[column] = value
  end
end

# 値を加工する
class ValueFilter
  # value を加工して返す
  # 配列を返した場合、カラムには配列が入る
  # カラムが配列の場合、 nil を返すと配列から取り除かれる
  def process(value, options)
  end
end

# ----------------------------------------------------------------------

# ListFilter を作成するユーティリティクラス
class FilterBuilder
  def initialize()
    @list_filter = ListFilter.new
  end

  def filter(filter)
    @list_filter.add filter
    self
  end

  # すべてのカラムに適用するフィルタ
  def all_columns(value_filter)
    @list_filter.add ColumnFilter.new(value_filter)
    self
  end
  
  # カラムフィルタを追加する
  def column(column_id, value_filter)
    for filter in Array(value_filter)
      @list_filter.add ColumnFilter.new(filter, column_id)
    end
    
    self
  end

  def result()
    @list_filter
  end

end

