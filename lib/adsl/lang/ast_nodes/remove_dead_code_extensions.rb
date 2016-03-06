module ADSL
  module Lang

    class ASTNode
      def returns?
        children.flatten.compact.any?{ |e| e.respond_to? :returns? and e.returns? }
      end
      
      def raises?
        children.flatten.compact.any?{ |e| e.respond_to? :raises? and e.raises? }
      end

      def remove_statements_after_returns(tail = [])
        if self.raises?
          return ASTRaise.new
        elsif self.returns?
          children_fields = children
          returning_child_index = children_fields.index &:returns?

          response = children_fields.first returning_child_index
          response << children_fields[returning_child_index].remove_statements_after_returns

          ASTBlock.new :exprs => response
        else
          if tail.empty?
            self
          else
            ASTBlock.new :exprs => [self] + tail
          end
        end
      end
    end

    class ASTAction
      def flatten_returns!
        @expr.block_replace do |node|
          next unless node.is_a? ASTReturnGuard
          flat_removes = node.expr.remove_statements_after_returns
          flat_removes.block_replace do |expr|
            next expr.expr if expr.is_a?(ASTReturn)
          end
          flat_removes
        end
      end
    end

    class ASTBlock
      def remove_statements_after_returns(tail = [])
        return_statuses = @exprs.map &:returns?
        
        if return_statuses.include? true
          first_return_index = return_statuses.index true
          @exprs = @exprs.first first_return_index + 1
          @exprs[-1] = @exprs.last.remove_statements_after_returns
        end

        return_statuses = @exprs.map &:returns?
        if return_statuses.include? nil
          first_maybe_return_index = return_statuses.index nil
          stmt = @exprs[first_maybe_return_index]
          tail = @exprs[(first_maybe_return_index + 1)..-1] + tail
          @exprs = @exprs.first first_maybe_return_index + 1
          @exprs[-1] = stmt.remove_statements_after_returns tail
        else
          @exprs += tail if return_statuses.uniq == [false]
        end

        self
      end

      def returns?
        results = @exprs.map(&:returns?)
        return true if results.any?{ |v| v == true }
        return nil  if results.any?{ |v| v == nil }
        false
      end

      def raises?
        results = @exprs.map(&:raises?)
        return true if results.any?{ |v| v == true }
        return nil  if results.any?{ |v| v == nil }
        false
      end
    end

    class ASTIf
      def returns?
        condition_returns = @condition.returns?
        branches_return = [@then_expr, @else_expr].map &:returns?
        return true if condition_returns or branches_return.all?{ |v| v == true }
        return false if condition_returns == false and branches_return.all? { |v| v == false }
        nil
      end

      def remove_statements_after_returns(tail = [])
        condition_returns = @condition.returns?
        if condition_returns == true
          @condition.remove_statements_after_returns
        elsif condition_returns == nil
          raise 'todo'
        else
          @then_expr = @then_expr.remove_statements_after_returns tail
          @else_expr = @else_expr.remove_statements_after_returns tail
          self
        end
      end
    end

    class ASTForEach
      def remove_statements_after_returns(tail = [])
        self
      end
    end

    class ASTReturn
      def remove_statements_after_returns(tail = [])
        self
      end
    end

    class ASTReturnGuard
      def remove_statements_after_returns(tail = [])
        raise 'This should never be called'
      end

      def returns?
        raise 'This should never be called'
      end
    end
  end
end
