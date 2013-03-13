module ModelFilterHelper
  # Dropdown select_box for comparison symbols
  #
  # Possible values of option_tags:
  # - nil (for default values provided at config acts_as_filterable);
  # - a hash of wanted descriptions and Arel predicates ({greater: :gt, equal: :eq});
  # - array of Arel predications ([:eq, :lt], etc). Can be used if defined default values
  #   for they (config.comparison_symbols = {lt: 'lt_text_descript', eq: 'is_equal'}).
  #
  # html_options - any html options (id, class, multiplicity, etc).
  def compar_symbols_select_for(field, option_tags = nil, html_options = {id: nil})
    theclass = controller.controller_name.classify.constantize
    filters_placement = obtain_config(:filters_placement, theclass)
    compar_suffix = obtain_config(:comparison_symbol_suffix, theclass)

    unless option_tags.is_a?(Hash)
      default_options = obtain_config(:comparison_symbols, theclass)

      # # if provided array, try to use it, else use default comparison_symbols
      option_tags = !option_tags.is_a?(Array) ?  default_options :
        (default_options.to_a | ModelFilter::ClassMethods.comparison_symbols.to_a).uniq{|k,v| v }.
          select{|k,v| option_tags.include?(v) }
    end

    option_tags_args = [option_tags]
    # add param for set selected option if needed
    option_tags_args << params[filters_placement]["#{field}_#{compar_suffix}"] if
      defined?(params[filters_placement]["#{field}_#{compar_suffix}"])

    select_tag "#{filters_placement}[#{field}_#{compar_suffix}]", options_for_select(*option_tags_args), html_options
  end

  private
    def obtain_config(adjustment, src_class = nil)
      src_class && src_class.respond_to?(adjustment) ? src_class.send(adjustment) :
        ModelFilter::ClassMethods.send(adjustment)
    end
  # end private
end
