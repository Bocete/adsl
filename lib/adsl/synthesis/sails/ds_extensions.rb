require 'adsl/ds/data_store_spec'
require 'adsl/util/general'
require 'active_support/core_ext/string/inflections'

module ADSL
  module DS

    class DSClass
      def to_sails_string(ast_spec)
        attributes = @members.map{ |m| m.to_sails_string ast_spec }
        sails_class_methods = @members.select{ |m| m.respond_to? :sails_class_methods }.map(&:sails_class_methods).flatten

        wsp = <<-ASD.match(/^(\s*)\w+$/)[1]
          str
        ASD
        return <<-NODEJS.strip_heredoc
          /**
          * #{ @name }.js
          *
          * @description :: TODO: You might write a short summary of how this model works and what it represents here.
          * @docs        :: http://sailsjs.org/#!documentation/models
          */
          
          module.exports = {
            attributes: {
              #{ attributes.join(",\n").gsub("\n", "\n#{wsp}    ") }
            },
            #{ sails_class_methods.join(",\n").gsub("\n", "\n#{wsp}  ") }
          };
        NODEJS
      end
    end

    class DSRelation
      attr_reader :sails_class_methods 
     
      def to_sails_string(ast_spec)
        prepare_sails_translation ast_spec
        options = []

        type = @sails_rel_type
        to_class = @to_class_name
        
        options << "#{type}: '#{@to_class.name}'"
        options << "required: true" if @cardinality.at_least_one?
        options << "via: '#{ @sails_via }'" unless @sails_via.nil?

        "#{@name}: {\n  #{ options.join ",\n  " }\n}"
      end
      
      def other_side(ast_spec)
        return @inverse_of if @inverse_of
        # maybe there exists a relation on the other side that is inverse to this one?
        candidates = @to_class.relations.select{ |m| m.inverse_of == self }
        return candidates.first unless candidates.empty?
        nil
      end

      def prepare_sails_translation(ast_spec)
        return unless @sails_class_methods.nil?

        @sails_other = other_side ast_spec
        
        stuff = if @sails_other.nil?
          if @cardinality.to_one?
            define_model
          else
            define_join
          end
        elsif @sails_other.cardinality.to_one?
          if @cardinality.to_one?
            @inverse_of_name.nil? ? define_model : define_collection
          else
            define_collection
          end
        else
          # other side is many
          if @cardinality.to_one?
            define_model
          else
            define_join
          end
        end
        stuff.each do |key, val|
          self.instance_variable_set "@#{key}", val
        end
      end

      def define_model
        {
          :sails_rel_type => 'model',
          :sails_via => nil,
          :sails_class_methods => [
            <<-DEREF.strip_heredoc,
              deref#{@name}: function(elems, cb) {
                if (elems.length == 0) {
                  cb(null, []);
                } else if (elems.length == 1) {
                  #{@to_class.name}.find({ id: elems[0].#{@name} }).exec(cb);
                } else {
                  #{@to_class.name}.find({ or: elems.map(function(e){ { id: e.#{@name} } }) }).exec(cb);
                }
              }
            DEREF
          ]
        }
      end

      def define_collection
        {
          :sails_rel_type => 'collection',
          :sails_via => @sails_other.name,
          :sails_class_methods => [
            <<-DEREF.strip_heredoc,
              deref#{@name}: function(elems, cb) {
                if (elems.length == 0) {
                  cb(null, []);
                } else if (elems.length == 1) {
                  #{@to_class.name}.find({ #{@sails_other.name}: elems[0].id }).exec(cb);
                } else {
                  #{@to_class.name}.find({ or: elems.map(function(e){ { #{@sails_other.name}: e.id } }) }).exec(cb);
                }
              }
            DEREF
          ]
        }
      end

      def define_join
        local_key = "#{ @from_class.name }_#{ @name }".downcase
        other_side_key = (@sails_other.nil? ?
                           "#{ @from_class.name }_#{ @name }_#{ @from_class.name }"
                         :
                           "#{ @to_class.name }_#{ @sails_other.name }"
                         ).downcase
        table_name = [local_key, other_side_key].sort.join '__'
        {
          :sails_rel_type => 'collection',
          :sails_via => @sails_other.nil? ? nil : @sails_other.name,
          :sails_class_methods => [
            <<-DEREF.strip_heredoc,
              deref#{@name}: function(elems, cb) {
                if (elems.length == 0) {
                  cb(null, []);
                } else if (elems.length == 1) {
                  #{@from_class.name}.findOne({ id: this.id }).populate('#{@name}').exec(function(err, from) {
                    if (err) {
                      cb(err, null)
                    } else {
                      cb(null, [from.#{@name}])
                    }
                  })
                } else {
                  #{@from_class.name}.find({ id: this.id }).populate('#{@name}').exec(function(err, froms) {
                    froms.map(function(f) {
                      // first dereference all elements
                      return f.#{@name}
                    }).reduce(function(a, b) {
                      // concatenate these arrays
                      return a.concat(b)
                    }).sort(function(a, b) {
                      // sort by id
                      return a.id - b.id
                    }).filter(function(value, index, self) {
                      // unique ids only
                      return index === 0 || value.id !== self[index-1].id
                    })
                  })
                }
              }
            DEREF
          ]
        }
      end
    end

    class DSField
      def to_sails_string(ast_spec)
        type_str = case type_sig
                   when ADSL::DS::TypeSig::BasicType::BOOL
                     'boolean'
                   when ADSL::DS::TypeSig::BasicType::STRING
                     'string'
                   when ADSL::DS::TypeSig::BasicType::INT
                     'integer'
                   when ADSL::DS::TypeSig::BasicType::DECIMAL
                     'float'
                   when ADSL::DS::TypeSig::BasicType::REAL
                     'float'
                   else
                     raise ArgumentError, "Unknown field type on #{@from_class.name}.#{@name}: #{type_sig}"
                   end
        "#{ @name }: { type: '#{ type_str }' }"
      end
    end

  end
end
