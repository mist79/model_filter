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

    # filters placement in params (e.g. params[:filters]
    DEFAULT_FILTERS_PLACEMENT = :filters

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
    # name and '_compar' suffix ('id - id_compar')
    #
    # Arguments hash can contain <tt><b>:ignore_blank_values => true (or false)</b></tt>
    # that overrides global settings once.
    def filtered(filters = {})
      to_filter = suitable_keys(filters)
      to_filter.empty? ? scoped : to_filter.inject(self){|injected, field|
        injected.with_value_of(field, filters[field], filters["#{field}_compar".to_sym])
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
        where(@areltable[field].send(compar_sym, wanted_value))
      end
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

    # shows if empty filters should be ignored
    def ignore_blank_values?
      defined?(@ignore_blank_values) ? @ignore_blank_values : send(:ignore_blank_values=, false)
    end

    # for ignoring blank values when filtering (e.g. Model.filtered({id: 1..3, name: ''})
    #
    # should be invoked as config when including to model
    def ignore_blank_values=(cond)
      raise ArgumentError, 'Condition must be true or false' unless
        cond.is_a?(TrueClass) || cond.is_a?(FalseClass)
      @ignore_blank_values = cond
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
      no_blanks = filters[:ignore_blank_values].nil? ?
        ignore_blank_values? : filters[:ignore_blank_values]
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
      end
    # end private
  end
end

::ActiveRecord::Base.send :include, ModelFilter::Base
