# encoding: utf-8

module ActiveRecordUtils

####
# simple (generic) database browser - no models required


class Browser  # also (formerly) known as connection manager

  # get connection names
  #  def connection_names
  #    ActiveRecord::Base.configurations.keys
  #  end

  CONNECTS = {}  # cache connections

  def connection_for( key )
    # cache connections - needed? why? why not??

    #  hack: for now only use cached connection if still active
    #   if not; get a new one to avoid connection closed errors in rails
    con = CONNECTS[ key ]
    if con
      puts "[Browser] cached connection found; con.active? #{con.active?}"
      unless con.active?
        puts "[Browser] *** reset cached connection (reason: connection stale/closed/not active)"
        con = CONNECTS[ key ] = nil
      end
    end

    if con.nil?
      con = CONNECTS[ key ] =  AbstractModel.connection_for( key )
    end

    # note: make sure connection is active?
    #  use verify!  - will try active? followed by reconnect!
    # - todo: check ourselves if active? - why? why not??
    #  -- not working w/ rails - after verify! still getting error w/ closed connection
    # -- con.verify!

    # wrap ActiveRecord connection in our own connection class
    Connection.new( con, key )
  end


  class AbstractModel < ActiveRecord::Base
    self.abstract_class = true   # no table; class just used for getting db connection

    def self.connection_for( key )
      establish_connection( key )
      connection
    end

  end # class AbstractModel


  class Connection

    def initialize( connection, key )
      @connection = connection
      @key        = key
    end

    attr_reader  :connection
    attr_reader  :key

    delegate :select_value, :select_all, :adapter_name,
             :to => :connection

    def class_name
      @connection.class.name
    end

  #    delegate :quote_table_name, :quote_column_name, :quote,
  #             :update, :insert, :delete,
  #             :add_limit_offset!,
  #             :to => :connection

    def tables
      @tables ||= fetch_table_defs
    end

    def table( name )
      tables.find { |t| t.name.downcase == name.downcase }
    end

    # getting list of column definitions
    # and order them to be more human readable
    def table_columns( name )
      cols = fetch_table_column_defs( name )
      ### fix/to be done
      # cols.sort_by{|col|
      #    [
      #      fields_to_head.index(col.name) || 1e6,
      #      -(fields_to_tail.index(col.name) || 1e6),
      #      col.name
      #    ]
      #  }
      cols
    end

    def fetch_table_defs
      @connection.tables.sort.map do |name|
        Table.new( self, name )
      end
    end

    def fetch_table_column_defs( name )
      ### fix/todo: add reference to table_def
      @connection.columns( name ).map do |col|
        Column.new( col.name, col.sql_type, col.default, col.null )
      end
    end


    def fetch_table_select_all( name, opts={} )
      limit =  (opts[:limit] || 33).to_i # 33 records limit/per page (for now default)
      limit =  33   if limit == 0   # use default page size if limit 0 (from not a number para)
      
      offset = (opts[:offset] || 0).to_i

      sql = "select * from #{name} limit #{limit}"

      sql << " offset #{offset}"   if offset > 0     # add offset if present (e.g greater zero)

      # page = (opts[:page] || 1 ).try(:to_i)
      # fields = opts[:fields] || nil
     
      # rez = { :fields => fields }
      # if sql =~ /\s*select/i && per_page > 0
      #  rez[:count] = select_value("select count(*) from (#{sql}) as t").to_i
      #  rez[:pages] = (rez[:count].to_f / per_page).ceil
      #  sql = "select * from (#{sql}) as t"
      #  add_limit_offset!( sql,
      #                        :limit => per_page,
      #                        :offset => per_page * (page - 1))
      # end

      result = {}
      result[ :sql  ] = sql    # note: lets also always add sql query to result too
      result[ :rows ] = select_all( sql )

      #    unless rez[:rows].blank?
      #      rez[:fields] ||= []
      #      rez[:fields].concat( self.sort_fields(rez[:rows].first.keys) - rez[:fields] )
      #    end

      Result.new( result )
    rescue StandardError => ex
      Result.new( error: ex )
    end  # fetch_table


=begin
      def column_names(table)
        columns(table).map{|c| c.name}
      end

      # fields to see first
      def fields_to_head
        @fields_to_head ||= %w{id name login value}
      end

      # fields to see last
      def fields_to_tail
        @fields_to_tail ||= %w{created_at created_on updated_at updated_on}
      end

      attr_writer :fields_to_head, :fields_to_tail

      # sort field names in a rezult
      def sort_fields(fields)
        fields = (fields_to_head & fields) | (fields - fields_to_head)
        fields = (fields - fields_to_tail) | (fields_to_tail & fields)
        fields
      end

      # performs query with appropriate method
      def query(sql, opts={})
        per_page = (opts[:perpage] || nil).to_i
        page = (opts[:page] || 1 ).try(:to_i)
        fields = opts[:fields] || nil
        case sql
        when /\s*select/i , /\s*(update|insert|delete).+returning/im
          rez = {:fields => fields}
          if sql =~ /\s*select/i && per_page > 0
            rez[:count] = select_value("select count(*) from (#{sql}) as t").to_i
            rez[:pages] = (rez[:count].to_f / per_page).ceil
            sql = "select * from (#{sql}) as t"
            add_limit_offset!( sql,
                              :limit => per_page,
                              :offset => per_page * (page - 1))
          end

          rez[:rows] = select_all( sql )

          unless rez[:rows].blank?
            rez[:fields] ||= []
            rez[:fields].concat( self.sort_fields(rez[:rows].first.keys) - rez[:fields] )
          end

          Result.new(rez)
        when /\s*update/i
          Result.new :value => update( sql )
        when /\s*insert/i
          Result.new :value => insert( sql )
        when /\s*delete/i
          Result.new :value => delete( sql )
        end
      rescue StandardError => e
        Result.new :error => e
      end

=end
      
  end # class Connection


  class Table

    def initialize(connection, name)
      @connection = connection
      @name       = name
    end

    attr_reader :connection
    attr_reader :name

    def count
      @connection.select_value( "select count(*) from #{name}").to_i
    end

    def columns
      # load columns on demand for now (cache on first lookup)
      @columns ||= @connection.table_columns( @name )
    end

    def query( opts={})
      @connection.fetch_table_select_all( @name, opts )
    end

  end # class Table


  class Column
    def initialize(name, type, default, null)
      @name    = name
      @type    = type   # note: is sql_type
      @default = default
      @null    = null   # note: true|false depending if NOT NULL or not
    end

    attr_reader :name, :type, :default, :null
  end # class Column


  class Result
    def initialize( opts={} )
      @sql = opts[:sql]  # sql statement as a string

      if opts[:error]
        @error = opts[:error]
      else
        @rows = opts[:rows]
        # @count = opts[:count] || @rows.size
        # @pages = opts[:pages] || 1
        # @fields = opts[:fields]
      end
    end

    attr_reader :sql, :rows, :error   ### to be done :count, :pages, :fields, 

    def error?()  @error.present?;       end
    def rows?()   @rows != nil;          end
  end # class Result


end # class Browser

end # module ActiveRecordUtils

