require 'sinatra'
require 'json'
require './textdb.rb'
require './vendors.rb'

class TextEase < Sinatra::Base
  post "/if_sync.json", :provides => :json do
    newestChange = Version.newest_version_change
    newParams = JSON.parse request.body.read, :symbolize_names => true
    
    puts "version in server : f:#{newestChange.fromVersion},t:#{newestChange.toVersion},c:#{newestChange.changesVector}"
    puts "version from client : f:#{newParams[:fromVersion]},t#{newParams[:toVersion]},c:#{newParams[:changesVector]}"
    
    if newestChange == nil || newestChange.toVersion < newParams[:toVersion]
      #can safely up load data
      sync_status(:upload, newestChange ? newestChange.toVersion.to_s : "0", "safe")
    elsif newestChange.toVersion > newParams[:toVersion]
      # get the corresponding version vector of newParams in server database
      # if the vector is the same, client can safely download data
      # else, client should upload the non-intersect portion of data
      vectorCorr = Version.vector_of_version(newParams[:fromVersion], newParams[:toVersion])
      
      puts "vectorInServer:#{vectorCorr}, client:#{newParams[:changesVector]}"
      
      if vectorCorr == newParams[:changesVector]
        totalVector = Version.vector_of_version(newParams[:toVersion])
        changesHash = {}
        parse_query_string totalVector, changesHash
        
        sync_status(:download, newestChange.toVersion, :safe, nil, changesHash)
      else
        totalVector = Version.vector_of_version(newParams[:fromVersion])
        newParamsHash, totalVectorHash = {}, {}
        parse_query_string(newParams[:changesVector], newParamsHash)
        parse_query_string(totalVector, totalVectorHash)
        
        shouldPostVector = non_intersect_hash_first_part newParamsHash, totalVectorHash
        shouldGetVector = intersect_hash(newParamsHash, totalVectorHash).merge!(\
        non_intersect_hash_first_part(totalVectorHash, newParamsHash))
        
        sync_status(:communicate, newestChange.toVersion, :unsafe, shouldPostVector, shouldGetVector)
      end
    else # newestChange.toVersion == newParams[:toVersion]
      # check vector and do the same task as the "else" case above
      vectorCorr = Version.vector_of_version(newParams[:fromVersion], newParams[:toVersion])
      if vectorCorr == newParams[:changesVector]
        sync_status(:synced, newestChange.toVersion, :safe)
      else
        newParamsHash, serverVectorHash = {}, {}
        parse_query_string(newParams[:changesVector], newParamsHash)
        parse_query_string(vectroCorr, serverVectorHash)
        
        shouldPostVector = non_intersect_hash_first_part newParamsHash, serverVectorHash
        shouldGetVector = intersect_hash(newParamsHash, serverVectorHash).merge!(\
        non_intersect_hash_first_part(serverVectorHash, newParamsHash))
        
        sync_status(:communicate, newestChange.toVersion, :unsafe, shouldPostVector, shouldGetVector)
      end
    end
  end
  
  get "/get.json", :provides => :json do # /get.json?1=id1&2=id2....
    textIdHash = {}
    parse_query_string(request.query_string, textIdHash)
    textArray = []
    
    textIdHash.each_value { |id|
      textArray << Text.first(:id => id)
    }
    
    get_text_status(textArray)
  end
  
  # /get_many_except.json?fromVersion=1&toVersion=2(&1=id1&2=id2&3=id3), exception in brackets
  get "/get_many_except.json", :provides => :json do
    # get fromVersion...toVersion changes
    paramsHash = {}
    parse_query_string(request.query_string, paramsHash)
    
    # filter and save the create & change entities,
    totalVector = Version.vector_of_version(paramsHash[:fromVersion], paramsHash[:toVersion])
    exceptionKeys = []
    exceptionHashSize, index = paramsHash.size - 2, 1
    while exceptionHashSize
      #parse_query_string_exception_for_values_or_keys() method will convert String to Symbol in this Array
      exceptionKeys << paramsHash["#{index}"]
      index += 1
      exceptionHashSize -= 1
    end
    createHash = {}
    parse_query_string_exception_for_values_or_keys(totalVector, createHash, ["delete"], exceptionKeys)
    
    # select and return them all to clients
    textArray = []
    createHash.each_key { |key|
      textArray << Text.first(:id => key)
    }
    
    get_text_status(textArray)
  end
  
  post "/update.json", :provides => :json do
    newParams = JSON.parse request.body.read, :symbolize_names => true
    successCount = 0
    failureIds = []
    
    if createArray = newParams[:create]
      createArray.each { |textParams|
        if Text.insert_or_replace(textParams)
          successCount += 1 
        else
          failureIds << textParams[:id]
        end
      }
    end
    
    if updateArray = newParams[:update]
      updateArray.each { |textParams|
        if text = Text.first(:id => textParams[:id])
          if text.update(:content => textParams[:content])
            successCount += 1 
          else
            failureIds << textParams[:id]
          end
        end
      }
    end
    
    if deleteArray = newParams[:delete]
      deleteArray.each { |textParams|
        if text = Text.first(:id => textParams[:id])
          if text.destroy
            successCount += 1 
          else
            failureIds << textParams[:id]
          end
        end
      }
    end
    
    if newChangesInfo = newParams[:versionInfo]
      Version.create_version((newChangesInfo[:changesVector])) unless newChangesInfo[:toVersion]
      Version.insert_version(newChangesInfo) if newChangesInfo[:toVersion]
    end
    
    post_text_status(successCount, failureIds)
  end
  
=begin
  post "/finish.json", :provides => :json do # finish.json?method=upload/download 
    queryHash = {}
    parse_query_string(request.query_string, queryHash)
    newParams = JSON.parse request.body.read, :symbolize_names => true
    
    if queryHash[:method] == "download"
      status 200
      Version.newest_version_change.to_json
    elsif queryHash[:method] == "upload"
      version = Version.create_version(newParams[:changeVector])
      
      status 200
      version.to_json
    else
      "error parameters"
    end
  end
=end

  get "/finish.json", :provides => :json do
    if version = Version.newest_version_change
      status 200
      {
        :fromVersion => version.fromVersion,
        :toVersion => version.toVersion,
        :changesVector => version.changesVector
        }.to_json
    end
  end

  helpers do
    def sync_status(actType, version, collision, *args)
      syncStatus = {
        :sync_act => actType,
        :version => version,
        :collision => collision
      }
      syncStatus[:get] = hash_to_params_string args[1] if args[1] && args[1].is_a?(Hash)
      if collision == :unsafe
        syncStatus[:post] = hash_to_params_string args[0] if args[0] && args[0].is_a?(Hash)
      end
      
      status 200
      syncStatus.to_json
    end
    
    def get_text_status(textArray)
      status = 200
      textArray.to_json
    end
    
    def post_text_status(successCount, *failureIds)
      status 200
      {
        :success => successCount,
        :failure => failureIds.to_json
      }.to_json
    end
    
  end
end