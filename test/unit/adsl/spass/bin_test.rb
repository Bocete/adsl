require 'adsl/spass/bin'
require 'test/unit'

class ADSL::Spass::SpassBinTest < Test::Unit::TestCase
  include ADSL::Spass::Bin

  def test_exec_spass__spass_on_path
    assert_nothing_raised do
      exec_spass(<<-SPASS)
        begin_problem(ProveTrue).
        
        list_of_descriptions.
          name({* *}).
          author({* *}).
          status(unsatisfiable).
          description({* *}).
        end_of_list.

        list_of_formulae(conjectures).
         formula(true).
        end_of_list.

        end_problem.
      SPASS
    end
  end
  
  def test_exec_spass__returns_correct
    assert_equal :correct, exec_spass(<<-SPASS)
      begin_problem(ProveTrue).
      
      list_of_descriptions.
        name({* *}).
        author({* *}).
        status(unsatisfiable).
        description({* *}).
      end_of_list.

      list_of_formulae(conjectures).
       formula(true).
      end_of_list.

      end_problem.
    SPASS
  end
  
  def test_exec_spass__returns_incorrect
    assert_equal :incorrect, exec_spass(<<-SPASS)
      begin_problem(ProveTrue).
      
      list_of_descriptions.
        name({* *}).
        author({* *}).
        status(unsatisfiable).
        description({* *}).
      end_of_list.

      list_of_formulae(conjectures).
       formula(false).
      end_of_list.

      end_problem.
    SPASS
  end
end
