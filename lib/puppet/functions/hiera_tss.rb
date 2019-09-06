Puppet::Functions.create_function(:hiera_tss) do

  require 'uri'
  require 'net/http'
  require 'json'

  dispatch :hiera_backend do
    param 'Variant[String, Numeric]', :key
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def hiera_backend(key, options, context)
    if !options.key?('uri')
      raise Puppet::DataBinding::LookupError, "Cannot use Secret Server backend: No URI defined."
    end

    if key =~ /^secret_server::.*/
      id = /secret_server::(\d.*)\w*/.match(key)[1]
      begin
        api_response = http_get(context, options, "secrets/#{id}")
        auth_info = api_response['items'].reduce({}) { |info, field|
          if field['fieldName'] == 'Username' || field['fieldName'] == 'Password'
            info[field['fieldName']] = field['itemValue']
          end
          info
        }
        return Puppet::Pops::Types::PSensitiveType::Sensitive.new(auth_info)
      rescue StandardError => e
        raise Puppet::DataBinding::LookupError, "Secret server lookup failed: #{e.message}"
      end

    else
      context.not_found
    end
  end

  def getSSLSettings(context, options)
    ssl_settings = {}
    ssl_settings[:use_ssl] = options['use_ssl']
    ssl_settings[:ca_path] = options['ca-path']
    ssl_settings[:ca_file] = options['ca_file']
    ssl_settings[:verify_mode] = options['ssl_verify'] ?  OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    return ssl_settings
  end

  def http_get(context, options, endpoint)
    uri = URI.parse(options['uri'])
    uri = URI.join(uri, '/SecretServer/api/v1/', endpoint)
    host, port, path = uri.host, uri.port, URI.escape(context.interpolate(uri.request_uri))
    
    access_token = authenticate(context, options)

    if context.cache_has_key(path)
      context.explain { "Returning cached value for #{path}" }
      return context.cached_value(path)
    else
      context.explain { "Querying #{uri}" }
      begin
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{access_token}"
        ssl_settings = getSSLSettings(context, options)

        response = Net::HTTP.start(host, port, ssl_settings) { |http|
          http.read_timeout = 5
          http.request(req)
        }

        if response.code == '200'
          context.cache(path, response)
          res_parsed = JSON.parse(response.body)
          return res_parsed
        elsif response.code == '400'
          context.explain { "400 Bad Request for #{uri}"}
          context.not_found
        
        else
          raise Puppet::DataBinding::LookupError, "secret server lookup failed. #{response.code} : #{response.message}"
        end
      rescue StandardError => e
        raise Puppet::DataBinding::LookupError, "secret server lookup failed #{e.message}"
      end
    end
  end

  def authenticate(context, options)
    return context.cached_value('access_token') if context.cache_has_key('access_token')
    uri = URI.parse(options['uri'])
    uri = URI.join(uri, '/SecretServer/', 'oauth2/token')
    host, port, path = uri.host, uri.port, URI.escape(context.interpolate(uri.request_uri))

    begin
      auth_info = context.cached_file_data(options['auth_file']) do |content|
        username = /^username\s*=\s*(\S*)\s*$/.match(content)
        password = /^password\s*=\s*(\S*)\s*$/.match(content)
        domain = /^domain\s*=\s*(\S*)\s*$/.match(content)
        raise "Couldn't parse auth file" unless username != nil && password != nil && domain != nil
        {'username' => username[1], 'password' => password[1], 'domain' => domain[1]}
      end
    rescue StandardError => e
      raise Puppet::DataBinding::LookupError, "Failed auth file parsing: #{e.message} at #{options['auth_file']}"
    end

    domain_user = defined?(auth_info['domain']) ? "#{auth_info['domain']}\\#{auth_info['username']}" : auth_info['username']
    post_data = { "username" => domain_user, "password" => auth_info["password"], "grant_type" => "password" }

    begin
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(post_data)
      ssl_settings = getSSLSettings(context, options)

      response = Net::HTTP.start(host, port, ssl_settings) { |http|
          http.read_timeout = 5
          http.request(req)
      }

      if response.code == '200'
        response = JSON.parse(response.body)
        context.cache('access_token', response['access_token'])
        return response['access_token'] 
      else
        raise Puppet::DataBinding::LookupError, "api response did not contain an authentication token: #{response.code} : #{response.message}"
      end
    rescue StandardError => e
      raise Puppet::DataBinding::LookupError, "secret server lookup failed #{e.message}"
    end
  end
end
