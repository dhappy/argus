module BookHelper
  def fname(str)
    str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    str.mb_chars.limit(254).to_s # this causes compatability issues
  end
end
