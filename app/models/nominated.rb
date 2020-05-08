class Nominated
  include Neo4j::ActiveRel
  before_save :translate_result

  from_class :Category
  to_class   [:Book, :Movie]
  type :NOM

  property :result, type: String

  def translate_result
    # https://sourceforge.net/p/isfdb/code-svn/HEAD/tree/trunk/common/awardClass.py#l28
    levels = {
      71 => 'No Winner: Insufficient Votes',
      72 => 'Not on Ballot: Insufficient Nominations',
      73 => 'No Award Given This Year',
      81 => 'Withdrawn',
      82 => 'Withdrawn: Nomination Declined',
      83 => 'Withdrawn: Conflict of Interest',
      84 => 'Withdrawn: Official Publication in a Previous Year',
      85 => 'Withdrawn: Ineligible',
      90 => 'Finalists',
      91 => 'Made First Ballot',
      92 => 'Preliminary Nominee',
      93 => 'Honorable Mention',
      98 => 'Early Submission',
      99 => 'Nomination Below Cutoff',
    }
    if self.result.to_i > 70
      self.result = levels[self.result.to_i]
    end
  end
end


