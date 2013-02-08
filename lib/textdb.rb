require 'data_mapper'
require 'dm-mysql-adapter'
require 'dm-pager'
require 'dm-aggregates'
require './vendors.rb'

load 'db_config.rb'

class Text
  include DataMapper::Resource
  
  property :id,                Integer,   :key => true
  property :title,             String
  property :content,           String
  property :time,              DateTime
  
  def self.insert_or_replace(params)
    if text = Text.first(:id => params[:id])
      text.update(:content => params[:content], :time => params[:time])
    else
      Text.create(:id => params[:id], :title => params[:title], :content => params[:content])
    end
  end
  
end

class Version
  include DataMapper::Resource
  
  property :id,                Serial
  property :fromVersion,       Integer
  property :toVersion,         Integer, :key => true
  property :changesVector,     String
  
  def self.vector_of_version(startVersion, toVersion=self.max(:toVersion))
    # TODO 1: avoid duplicate of items
    # TODO 2: if not exists the version Vector, this function will become a infinite loop
    tempVersion = Version.first(:fromVersion => startVersion, :toVersion => toVersion)
    if tempVersion
      # return the vector if there's a data directly
      tempVersion.changesVector
    else
      # get the total vector from startVersion to toVersion
      toVersion = startVersion + 1
      changesVector = ""
      while tempVersion = Version.first(:toVersion => toVersion)
        changesVector << "&#{tempVersion.changesVector}" if changesVector.length > 0
        changesVector << tempVersion.changesVector if changesVector.length == 0
        toVersion = toVersion + 1
      end
      
      if changesVector.length
        changesVector
      else
        nil
      end
    end
  end
  
  def self.newest_version_change
    version = Version.first(:toVersion => self.max(:toVersion))
    unless version
      version = self.insert_version({:fromVersion => 0, :toVersion => 0, :changesVector => ""})
    end
    version
  end
  
  def self.create_version(changeVector)
    fromVersion = self.newest_version_change.toVersion
    toVersion = fromVersion + 1
    Version.create(:fromVersion => fromVersion, :toVersion => toVersion, :changeVector => changeVector)
  end
  
  def self.insert_version(versionInfo)
    fromVersion = versionInfo[:fromVersion]
    toVersion = versionInfo[:toVersion]
    Version.create(:fromVersion => fromVersion, :toVersion => toVersion, :changesVector => versionInfo[:changesVector])
  end
  
end

DataMapper.finalize
#DataMapper.auto_migrate!
DataMapper.auto_upgrade!