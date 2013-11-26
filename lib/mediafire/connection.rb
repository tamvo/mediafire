require 'uri'
require 'net/http'
require 'net/http/post/multipart'
require 'net/http/uploadprogress'

# Net::HTTP.version_1_1

module Mediafire
  module Connection
    ENDPOINT = 'http://www.mediafire.com/'

    def get(path, options={})
      request(:get, path, options)
    end

    def post(path, options={})
      request(:post, path, options)
    end

    def request(method, path, options)
      uri = URI.parse("#{ENDPOINT}#{path}")

      request = nil
      if method == :get
        request = Net::HTTP::Get.new(uri.request_uri)
      elsif method == :post
        if has_multipart? options
          request = Net::HTTP::Post::Multipart.new(uri.request_uri, options)
        else
          request = Net::HTTP::Post.new(uri.request_uri)
          request.set_form_data(options)
        end
      end
      request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.2 (KHTML, like Gecko) Chrome/15.0.874.120 Safari/535.2'
      request['Cookie'] = cookie

      if has_multipart? options
        t = Thread.new do
          loop do
            @s_queue.pop.call request.upload_size
          end
        end
        options.values.each do |v|
          if v.is_a? UploadIO
            t[:filename] = v.original_filename
          end
        end
      end
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end
      t.kill if has_multipart? options
      check_statuscode(response)
      build_cookie(response.get_fields('Set-Cookie'))

      return response
    end

    def has_multipart?(options={})
      options.values.each do |v|
        if v.is_a? UploadIO
          return true
        end
      end
      false
    end

    def upload_size(filename)
      Thread.list.each do |t|
        if t[:filename] == filename
          @s_queue.push Proc.new {|n| @r_queue.push n}
          return @r_queue.pop
        end
      end
      0
    rescue Timeout::Error => e
      return nil
    end

    private

    def check_statuscode(response)
      case response.code
      when 400
        raise BadRequest
      when 401
        raise Unauthorized
      when 403
        raise Forbidden
      when 404
        raise NotFound
      when 406
        raise NotAcceptable
      when 408
        raise RequestTimeout
      when 500
        raise InternalServerError
      when 502
        raise BadGateway
      when 503
        raise ServiceUnavailable
      end
    end

    def cookie
      s = []
      @cookie.each do |k,v|
        s.push "#{k}=#{v}"
      end
      s.join(';')
    end

    def build_cookie(cookies)
      cookies.each do |n|
        c = n[0...n.index(';')].match(/(.*)=(.*)/)
        @cookie[c[1]] = c[2] if c
      end if cookies
    end
  end
end
