module ADSL
  module Lang

    class HaltingStatus
      attr_accessor :returns, :raises

      def initialize(opts = {})
        opts[:returns] ||= :never
        opts[:raises]  ||= :never
        @returns = opts[:returns]
        @raises  = opts[:raises]
      end

      def and(other)
        self.dup.and! other
      end

      def and!(other)
        @returns = HaltingStatus.max_strength @returns, other.returns
        @raises  = HaltingStatus.max_strength @raises,  other.raises
        self
      end

      def self.max_strength(times1, times2)
        return :always    if times1 == :always    || times2 == :always
        return :sometimes if times1 == :sometimes || times2 == :sometimes
        return :never
      end

      [:raises, :returns].each do |op|
        [:never, :sometimes, :always].each do |times|
          # def raises_never?
          #   raises == :never
          # end
          send :define_method, "#{op}_#{times}?" do
            send(op) == times
          end
        end
      end

      def halts_always?
         returns_always? || raises_always?
      end
      
      def halts_sometimes?
        !halts_never?
      end

      def halts_never?
        returns_never? && raises_never?
      end

      def dup
        HaltingStatus.new :returns => @returns, :raises => @raises
      end
    end

    class ASTNode
      def halting_status
        return @halting_status if @halting_status
        @halting_status = gen_halting_status
        @halting_status
      end

      def flush_halting_status
        @halting_status = nil
        children.flatten.each do |e|
          e.flush_halting_status if e.respond_to? :flush_halting_status
        end
      end

      def gen_halting_status
        might_return, might_raise = false, false
        children.flatten.compact.each do |e|
          next unless e.respond_to? :halting_status

          sub_hs = e.halting_status
          if sub_hs.returns_sometimes?
            might_return = true
          elsif sub_hs.returns_always?
            if might_raise
              return HaltingStatus.new :returns => :sometimes, :raises => :sometimes
            else
              return HaltingStatus.new :returns => :always, :raises => :never
            end
          end
          if sub_hs.raises_sometimes?
            might_raise = true
          elsif sub_hs.raises_always?
            if might_return
              return HaltingStatus.new :returns => :sometimes, :raises => :sometimes
            else
              return HaltingStatus.new :returns => :never, :raises => :always
            end
          end
        end
        HaltingStatus.new(
          :returns => (might_return ? :sometimes : :never),
          :raises  => (might_raise  ? :sometimes : :never)
        )
      end

      def raises?
        halting_status.raises_always?
      end

      def returns?
        halting_status.returns_always?
      end

      def remove_statements_after_returns(tail = [])
        return self if no_statements_after_returns? && tail.empty?
        if halting_status.returns_always?
          children_fields = children
          returning_child_index = children_fields.index{ |e| e.halting_status.returns_always? }

          exprs = children_fields.first returning_child_index
          exprs << children_fields[returning_child_index].remove_statements_after_returns

          ASTBlock.new :exprs => exprs
        elsif halting_status.returns_sometimes?
          raise 'todo'
        else
          if tail.empty?
            self
          else
            ASTBlock.new :exprs => [self] + tail
          end
        end
      end

      def no_statements_after_returns?
        return true if halting_status.returns_never?
        children_fields = children.select{ |c| c.respond_to? :no_statements_after_returns? }
        return true if children_fields.empty?
        return children_fields[0..-2].all?{ |c| c.halting_status.returns_never? } && children_fields.last.no_statements_after_returns?
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
          flat_removes.flush_halting_status
          flat_removes
        end
      end
    end
    
    class ASTEmptyObjset
      def remove_statements_after_returns(tail = [])
        return self if tail.empty?
        return tail.first if tail.length == 1
        ASTBlock.new(:exprs => tail).remove_statements_after_returns([])
      end
    end

    class ASTBlock

      def remove_statements_after_returns(tail = [])
        return self if no_statements_after_returns? && tail.empty?

        to_flush = false

        always_returning_index = @exprs.index{ |e| e.halting_status.returns_always? }

        if always_returning_index
          @exprs = @exprs.first always_returning_index + 1
          @exprs[-1] = @exprs.last.remove_statements_after_returns
          to_flush = true
        end

        sometimes_returning_index = @exprs.index{ |e| e.halting_status.returns_sometimes? }
        if sometimes_returning_index
          stmt = @exprs[sometimes_returning_index]
          tail = @exprs[(sometimes_returning_index+1)..-1] + tail
          @exprs = @exprs.first sometimes_returning_index + 1
          @exprs[-1] = stmt.remove_statements_after_returns tail
          to_flush = true
        elsif @exprs.all?{ |e| e.halting_status.returns_never? }
          @exprs += tail
          to_flush = true
        end

        # the tail might have had returns and whatnot, so lets run this again just to clean that up
        remove_statements_after_returns([]) if tail.any?

        flush_halting_status if to_flush
        self
      end
    end

    class ASTIf
      def gen_halting_status
        hs = @condition.halting_status
        
        then_status = hs.and @then_expr.halting_status
        else_status = hs.and @else_expr.halting_status

        if then_status.returns == else_status.returns
          returns = then_status.returns
        else
          returns = :sometimes
        end
        if then_status.raises == else_status.raises
          raises = then_status.raises
        else
          raises = :sometimes
        end

        HaltingStatus.new :returns => returns, :raises => raises
      end

      def no_statements_after_returns?
        @condition.halting_status.returns_never? && @then_expr.no_statements_after_returns? && @else_expr.no_statements_after_returns?
      end

      def remove_statements_after_returns(tail = [])
        return self if no_statements_after_returns? && tail.empty?

        if @condition.halting_status.returns_always?
          @condition.remove_statements_after_returns
        elsif @condition.halting_status.returns_sometimes?
          # we want the branch to happen only when the condition does not return
          raise 'todo'
        else
          @then_expr = @then_expr.remove_statements_after_returns tail
          @else_expr = @else_expr.remove_statements_after_returns tail.deep_dup
        end
        flush_halting_status
        self
      end
    end

    class ASTForEach
      def remove_statements_after_returns(tail = [])
        self
      end

      def gen_halting_status
        hs = @objset.halting_status
        
        # we don't support loop bodies returning yet
        returns = hs.returns
        hs = hs.and @expr.halting_status
        hs.returns = returns

        hs
      end
    end

    class ASTReturn
      def remove_statements_after_returns(tail = [])
        self
      end

      def gen_halting_status
        hs = super
        hs.returns = :always unless hs.raises_always?
        hs
      end
    end

    class ASTRaise
      def gen_halting_status
        HaltingStatus.new :raises => :always, :returns => :never
      end
    end

    class ASTReturnGuard
      def gen_halting_status
        hs = super
        hs.returns = :never
        hs
      end
    end
  end
end
