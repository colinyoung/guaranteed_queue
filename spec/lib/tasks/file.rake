module FileIncrement
  Filename = "increment_file_by.txt"
  Path = File.dirname(__FILE__) + '/../../tmp'
  AbsolutePath = Path + '/' + Filename

  def self.prepare!
    FileUtils.mkdir_p Path
    File.open(AbsolutePath, 'w') {|f| f.write '0' }
  end
end

namespace :file do

  task :increment_by do |t, args|

    inc_by = Integer(args.first || 1)
    
    file = File.open(absolute_path, 'r')

    digit = Integer file.read

    file = File.open(absolute_path, 'w')
    
    file.write digit + inc_by
  end

  private

  def absolute_path
    FileIncrement::Path + '/' + FileIncrement::Filename
  end

end
