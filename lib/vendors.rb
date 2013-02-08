#require "jcode"

# parameter should be an Array of hash keys
def symbolize_keys(keys)
  keys.collect! { |obj|
    obj.to_sym if obj.is_a? String
  } if keys.is_a? Array
end

def parse_query_string(str, chngData={})
  # chngData should comes from old to new
  # change log is saved like this - delete=id1&change=id2&create=id3
  str.split("&").each { |single| 
    pair = single.split("=")
    chngData[pair[0].to_sym] = pair[1]
  }
end

def parse_query_string_exception_for_values_or_keys(str, chngData={}, exceptionValues=[], exceptionKeys=[])
  
  parse_query_string(str, chngData)
  symbolize_keys exceptionKeys
  
  unless exceptionValues.empty? && exceptionKeys.empty?
    chngData.each_pair { |key, value|
      if exceptionValues.include?(value)
        chngData.delete(key)
      elsif exceptionKeys.include?(key)
        chngData.delete(key)
      end
    }
  end
end
=begin
def non_intersect_hash(hash1={}, hash2={})
  return nil if hash1.empty? && hash2.empty?
  return hash2 if hash1.empty? || !hash1
  return hash1 if hash2.empty? || !hash2
  
  result = hash1.dup
  result.each_pair { |key, value|
    if hash2.include? key
      result.delete(key)
      hash2.delete(key)
    end
  }
  hash2.each_pair { |key, value|
    result[key.to_sym] = value.dup;
  }
  
  if result.empty?
    nil
  else
    result
  end
end
=end
def intersect_hash(hash1={}, hash2={})
  return nil if hash1.empty? || hash2.empty
  
  result = hash1.dup
  result.each_pair { |key, value|
    if !(hash2.include? key)
      result.delete(key)
    end
  }
  if result.empty?
    nil
  else
    result
  end
end

def non_intersect_hash_first_part(hash1={}, hash2={})
  return nil if hash1.empty?
  return hash1 if hash2.empty?
  
  result = hash1.dup
  result.each_pair { |key, value|
    if hash2.include? key
      result.delete key
    end
  }
  if result.empty?
    nil
  else
    result
  end
end

def hash_to_params_string(hash)
  result = ""
  hash.each_pair { |key, value|
    if result.length > 1
      result += "&#{key}=#{value}"
    else
      result += "#{key}=#{value}"
    end
  }
  result
end