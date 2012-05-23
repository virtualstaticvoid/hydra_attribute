module HydraAttribute
  module ActiveRecord
    module Relation
      def self.extended(base)
        base.singleton_class.send :alias_method_chain, :where, :hydra_attribute
      end

      define_method HydraAttribute.config.relation_execute_method do
        records = super()
        if records.many?
          group_hydra_records_by_type(records).each_value do |hydra_hash|
            ::ActiveRecord::Associations::Preloader.new(hydra_hash[:records], hydra_hash[:association]).run if hydra_hash[:records].any?
          end
        end
        records
      end

      def where_with_hydra_attribute(opts, *rest)
        return self if opts.blank?

        if opts.is_a?(Hash)
          opts.inject(self) do |relation, (name, value)|
            if klass.hydra_attribute_names.include?(name)
              relation = relation.clone
              relation.joins_values += build_hydra_joins_values(name, value)
              relation.where_values += build_where(build_hydra_where_options(name, value))
              relation
            else
              relation.where_without_hydra_attribute(name => value)
            end
          end
        else
          where_without_hydra_attribute(opts, *rest)
        end
      end

      def order(*args)
        return self if args.blank?

        relation = clone
        relation.hydra_order_values |= (args.flatten & klass.hydra_attribute_names)
        relation.order_values += (args.flatten - klass.hydra_attribute_names)
        relation
      end

      if ::ActiveRecord::VERSION::MINOR > 1
        def reorder(*args)
          return self if args.blank?

          relation = clone
          relation.hydra_order_values = []
          relation.reordering_value = true
          relation.order_values = args.flatten
          relation
        end
      end

      # Should lazy join appropriate hydra tables for order fields
      # because it is impossible to predict what join type should be used
      def build_arel
        # should not care about double #joins_values modification
        # because #arel method is cacheable
        hydra_order_values.each do |attribute|
          join_alias = hydra_ref_alias(attribute, 'inner')
          join_alias = hydra_ref_alias(attribute, nil) unless hydra_join_values.has_key?(join_alias)

          self.joins_values += build_hydra_joins_values(attribute, nil) unless hydra_join_values.has_key?(join_alias)
          self.order_values += [klass.connection.quote_table_name(join_alias) + '.' + klass.connection.quote_column_name('value')]
        end

        super
      end

      protected

      def hydra_join_values
        @hydra_join_values ||= {}
      end

      def hydra_order_values
        @hydra_order_values ||= []
      end

      def hydra_order_values=(value)
        @hydra_order_values = value
      end

      private

      def build_hydra_joins_values(name, value)
        ref_alias = hydra_ref_alias(name, value)

        return [] if hydra_join_values.has_key?(ref_alias)
        hydra_join_values[ref_alias] = value

        conn             = klass.connection
        quoted_ref_alias = conn.quote_table_name(ref_alias)

        [[
          "#{hydra_join_type(value)} JOIN",
          conn.quote_table_name(hydra_ref_table(name)),
          'AS',
          quoted_ref_alias,
          'ON',
          "#{klass.quoted_table_name}.#{klass.quoted_primary_key}",
          '=',
          "#{quoted_ref_alias}.#{conn.quote_column_name(:entity_id)}",
          'AND',
          "#{quoted_ref_alias}.#{conn.quote_column_name(:entity_type)}",
          '=',
          conn.quote(klass.base_class.name),
          'AND',
          "#{quoted_ref_alias}.#{conn.quote_column_name(:name)}",
          '=',
          conn.quote(name)
        ].join(' ')]
      end

      def build_hydra_where_options(name, value)
        {hydra_ref_alias(name, value).to_sym => {value: value}}
      end

      def hydra_ref_class(name)
        type = klass.hydra_attribute_types.find { |type| klass.hydra_attributes[type].include?(name) }
        HydraAttribute.config.associated_model_name(type).constantize
      end

      def hydra_ref_table(name)
        hydra_ref_class(name).table_name
      end

      def hydra_ref_alias(name, value)
        hydra_ref_table(name) + '_' + hydra_join_type(value).downcase + '_' + name.to_s
      end

      def hydra_join_type(value)
        value.nil? ? 'LEFT' : 'INNER'
      end

      def hydra_hash_with_associations
        SUPPORT_TYPES.each_with_object({}) do |type, hash|
          hash[type] = {association: HydraAttribute.config.association(type), records: []}
        end
      end

      def group_hydra_records_by_type(records)
        records.each_with_object(hydra_hash_with_associations) do |record, hydra_hash|
          if record.class.instance_variable_defined?(:@hydra_attributes) # not all classes have defined hydra attributes
            record.class.hydra_attribute_types.each do |type|
              hydra_hash[type][:records] << record unless record.association(hydra_hash[type][:association]).loaded?
            end
          end
        end
      end

    end
  end
end