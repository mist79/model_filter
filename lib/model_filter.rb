# module that provides model filtering behavior
module ModelFilter

  # Engine inclusion for automatic rails ../app/ loading
  class Engine < Rails::Engine
  end

  module Base
    def self.included(base)
      base.extend Config
    end

    module Config
      def acts_as_filterable
        extend ClassMethods
        yield self if block_given?
        privatize_config
      end
    end
  end

  module ClassMethods
    extend self

    # filters placement in params (e.g. params[:filters])
    DEFAULT_FILTERS_PLACEMENT = :filters

    # suffix to detect comparison symbol "field" in filters' hash
    # comparison symbol for field 'amount' will be search in filters[:amount_compar] by default
    DEFAULT_COMPARISON_SYMBOL_FIELD_SUFFIX = :compar

    DEFAULT_IGNORE_BLANK_VALUES_PRESET = true

    DEFAULT_COMPARISON_SYMBOLS = {
      '='  => :eq,
      '<'  => :lt,
      '>'  => :gt,
      '<=' => :lteq,
      '>=' => :gteq,
      '!=' => :not_eq
    }

    # Usage:
    #   MyModel.filtered({:id => 3, :col2 => 1..9, :col2_compar => :not_in})
    # method expects that comparison symbols param names composed of column
    # name and '_compar' suffix ('id - id_compar'). Suffix is configurable.
    #
    # Arguments hash can contain <tt><b>:ignore_blank_values => true (or false)</b></tt>
    # that overrides global settings once.
    def filtered(raw_filters = {})
      filters = raw_filters.symbolize_keys
      to_filter = suitable_keys(filters)
      to_filter.empty? ? scoped : to_filter.inject(self){|injected, field|
        injected.with_value_of(field, filters[field.to_sym], filters["#{field}_#{comparison_symbol_suffix}".to_sym])
      }
    end

    # Usage:
    #   MyModel.with_value_of(:id, 3..5)
    #   MyModel.with_value_of(:id, 3, :eq)
    #   MyModel.with_value_of(:id, [3,5,12], :not_in)
    def with_value_of(field, wanted_value, compar_sym = nil)
      compar_sym ||= wanted_value.is_a?(Array) || wanted_value.is_a?(Range) ? :in : :eq
      @areltable ||= arel_table
      mapping = filter_mappings[field]
      if mapping
        send(mapping, wanted_value, compar_sym)
      else
        advanced_fields.include?(field) && [:eq, :in, :not_eq, :not_in].include?(compar_sym.to_sym) ?
          special_numeric_filter(field, wanted_value, compar_sym) :
          where(@areltable[field].send(compar_sym, wanted_value))
      end
    end

    # Any comparison symbol will be transformed to :eq, :not_eq, :in, :not_in
    # depend on presence 'not' part
    #
    # Whitespaces in digits_str argument will be ignored
    #
    # Usage:
    #   MyModel.special_numeric_filter(:id, "1, 2, 5 - 7.3", :eq)
    #     #=> (my_models.id BETWEEN 5.0 AND 7.3 OR my_models.id IN (1.0, 2.0))
    #   MyModel.special_numeric_filter(:id, "1, 2, 5 - 7.3", :not_eq)
    #     #=> my_models.id < 5.0 OR my_models.id > 7.3 AND my_models.id NOT IN (1.0, 2.0)
    def special_numeric_filter(col, digits_str, compar_sym = nil)
      compar_prefix = /not/ === compar_sym ? 'not_' : ''
      statements_binder = compar_prefix.blank? ? :or : :and

      arel_tbl = arel_table
      prepared_conds = digits_str.to_s.split(',').
        map{|ar| ar.gsub(/[^\d.-]/, '')}.
        each_with_object({in_conds: [], between_conds: []}){|to_parse, hash|
          el = to_parse.split('-').map(&:to_f).minmax.delete_if(&:nil?).uniq
          if el.one?
            hash[:in_conds] |= el
          elsif el.size == 2
            hash[:between_conds] |= [Range.new(*el)]
          end
        }
      arel_query = (prepared_conds[:between_conds] | [prepared_conds[:in_conds]].delete_if(&:blank?)).map{|el|
        conds = (el.is_a?(Array) && el.one?) ? ["#{compar_prefix}eq", el.first] : ["#{compar_prefix}in", el]
        arel_tbl[col].send(*conds)
      }.inject(statements_binder)
      where(arel_query)
    end

    # for use in views
    #
    # Usage:
    #   <%= select_tag 'id_compar', options_for_select(MyModel.comparison_symbols) %>
    def comparison_symbols
      defined?(@comparison_symbols) ? @comparison_symbols : send(:comparison_symbols=, :default)
    end

    # set list of comparison symbols that will be used in views
    #
    # should be invoked as config when including to model
    def comparison_symbols=(syms)
      raise ArgumentError, 'Must have :default or Hash as parameter' unless
        (syms == :default) || syms.is_a?(Hash)

      # most common operators for default
      @comparison_symbols = syms == :default ? DEFAULT_COMPARISON_SYMBOLS : syms
    end

    # for internal use
    def comparison_symbol_suffix
      defined?(@comparison_symbol_suffix) ? @comparison_symbol_suffix :
        send(:comparison_symbol_suffix=, DEFAULT_COMPARISON_SYMBOL_FIELD_SUFFIX)
    end

    # sets suffix for filter field where will be search comparison symbol for it
    #
    # should be invoked as config when including to model
    def comparison_symbol_suffix=(suffix)
      @comparison_symbol_suffix = suffix
    end

    # shows if empty filters should be ignored
    def ignore_blank_values?
      defined?(@ignore_blank_values) ? @ignore_blank_values : send(:ignore_blank_values=, DEFAULT_IGNORE_BLANK_VALUES_PRESET)
    end

    # for ignoring blank values when filtering (e.g. Model.filtered({id: 1..3, name: ''})
    #
    # should be invoked as config when including to model
    def ignore_blank_values=(cond)
      raise ArgumentError, 'Condition must be true or false' unless
        cond.is_a?(TrueClass) || cond.is_a?(FalseClass)
      @ignore_blank_values = cond
    end

    # fields for which will be used special_numeric_filter (only numeric and positive)
    def advanced_fields
      defined?(@advanced_fields) ? @advanced_fields : send(:advanced_fields=, [])
    end

    # should be invoked as config when including to model
    def advanced_fields=(fields)
      raise ArgumentError, 'Argument must be an Array' unless fields.is_a?(Array)
      @advanced_fields = fields
    end

    # where filters placed in params (for controllers/views)
    def filters_placement
      defined?(@filters_placement) ? @filters_placement : send(:filters_placement=, DEFAULT_FILTERS_PLACEMENT)
    end

    # should be invoked as config when including to model
    def filters_placement=(placement)
      @filters_placement = placement
    end

    # list columns which will be filtered by Model.filtered method
    def enabled_filters
      defined?(@enabled_filters) ? @enabled_filters : send(:enabled_filters=, :all)
    end

    # set columns for filtering by Model.filtered method
    #
    # should be invoked as config when including to model
    def enabled_filters=(filters)
      raise ArgumentError, 'Must have :all or Array as parameter' unless
        filters == :all || filters.is_a?(Array)
      @enabled_filters = filters == :all ?
        column_names.map(&:to_sym) | filter_mappings.keys : filters
    end

    # list of remapped filter methods for certain columns (and for 'virtual'
    # columns)
    def filter_mappings
      defined?(@filter_mappings) ? @filter_mappings : send(:filter_mappings=, {})
    end

    # set mappings for filtering by Model.filtered method
    #
    # should be invoked as config when including to model
    def filter_mappings=(mappings)
      raise ArgumentError, 'Must have a Hash as parameter' unless mappings.is_a?(Hash)
      @filter_mappings = mappings
    end

    # returns columns which will be processed by filter (Model.filtered)
    #
    # for internal use
    def suitable_keys(filters = {})
      no_blanks = filters.fetch(:ignore_blank_values, ignore_blank_values?)
      wanted_keys = no_blanks ? filters.select{|k,v| v.present? }.keys : filters.keys
      enabled_filters & wanted_keys
    end

    private
      def privatize_config
        private_class_method :enabled_filters=
        private_class_method :filter_mappings=
        private_class_method :comparison_symbols=
        private_class_method :ignore_blank_values=
        private_class_method :filters_placement=
        private_class_method :advanced_fields=
        private_class_method :comparison_symbol_suffix=
      end
    # end private
  end  # ClassMethods
end

::ActiveRecord::Base.send :include, ModelFilter::Base
