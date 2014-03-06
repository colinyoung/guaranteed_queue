require 'spec_helper'

describe 'tasks' do

  let(:path) { FileIncrement::Path }
  let(:filename) { FileIncrement::Filename }
  let(:absolute_path) { FileIncrement::Path + '/' + FileIncrement::Filename }

  it 'should increment the file by the argument' do
    FileIncrement.prepare!
    Rake.application.invoke_task "file:increment_by[1]"
  end

  after :all do
    FileUtils.rm absolute_path
  end
end