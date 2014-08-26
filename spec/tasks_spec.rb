require 'spec_helper'

describe 'tasks' do

  ABSOLUTE_PATH = FileIncrement::Path + '/' + FileIncrement::Filename

  let(:path) { FileIncrement::Path }
  let(:filename) { FileIncrement::Filename }
  let(:absolute_path) { ABSOLUTE_PATH }

  it 'should increment the file by the argument' do
    FileIncrement.prepare!
    Rake.application.invoke_task "file:increment_by[1]"
  end

  after :all do
    FileUtils.rm ABSOLUTE_PATH
  end
end
