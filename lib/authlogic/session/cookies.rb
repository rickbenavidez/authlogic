module Authlogic
  module Session
    # Handles all authentication that deals with cookies, such as persisting,
    # saving, and destroying.
    module Cookies
      VALID_SAME_SITE_VALUES = [nil, "Lax", "Strict"].freeze

      def self.included(klass)
        klass.class_eval do
          extend Config
          include InstanceMethods
          persist :persist_by_cookie
          after_save :save_cookie
          after_destroy :destroy_cookie
        end
      end

      # Configuration for the cookie feature set.
      module Config
        # The name of the cookie or the key in the cookies hash. Be sure and use
        # a unique name. If you have multiple sessions and they use the same
        # cookie it will cause problems. Also, if a id is set it will be
        # inserted into the beginning of the string. Example:
        #
        #   session = UserSession.new
        #   session.cookie_key => "user_credentials"
        #
        #   session = UserSession.new(:super_high_secret)
        #   session.cookie_key => "super_high_secret_user_credentials"
        #
        # * <tt>Default:</tt> "#{klass_name.underscore}_credentials"
        # * <tt>Accepts:</tt> String
        def cookie_key(value = nil)
          rw_config(:cookie_key, value, "#{klass_name.underscore}_credentials")
        end
        alias_method :cookie_key=, :cookie_key

        # If sessions should be remembered by default or not.
        #
        # * <tt>Default:</tt> false
        # * <tt>Accepts:</tt> Boolean
        def remember_me(value = nil)
          rw_config(:remember_me, value, false)
        end
        alias_method :remember_me=, :remember_me

        # The length of time until the cookie expires.
        #
        # * <tt>Default:</tt> 3.months
        # * <tt>Accepts:</tt> Integer, length of time in seconds, such as 60 or 3.months
        def remember_me_for(value = nil)
          rw_config(:remember_me_for, value, 3.months)
        end
        alias_method :remember_me_for=, :remember_me_for

        # Should the cookie be set as secure?  If true, the cookie will only be sent over
        # SSL connections
        #
        # * <tt>Default:</tt> true
        # * <tt>Accepts:</tt> Boolean
        def secure(value = nil)
          rw_config(:secure, value, true)
        end
        alias_method :secure=, :secure

        # Should the cookie be set as httponly?  If true, the cookie will not be
        # accessible from javascript
        #
        # * <tt>Default:</tt> true
        # * <tt>Accepts:</tt> Boolean
        def httponly(value = nil)
          rw_config(:httponly, value, true)
        end
        alias_method :httponly=, :httponly

        # Should the cookie be prevented from being send along with cross-site
        # requests?
        #
        # * <tt>Default:</tt> nil
        # * <tt>Accepts:</tt> String, one of nil, 'Lax' or 'Strict'
        def same_site(value = nil)
          unless VALID_SAME_SITE_VALUES.include?(value)
            msg = "Invalid same_site value: #{value}. Valid: #{VALID_SAME_SITE_VALUES.inspect}"
            raise ArgumentError, msg
          end
          rw_config(:same_site, value)
        end
        alias_method :same_site=, :same_site

        # Should the cookie be signed? If the controller adapter supports it, this is a
        # measure against cookie tampering.
        def sign_cookie(value = nil)
          if value && !controller.cookies.respond_to?(:signed)
            raise "Signed cookies not supported with #{controller.class}!"
          end
          rw_config(:sign_cookie, value, false)
        end
        alias_method :sign_cookie=, :sign_cookie
      end

      # The methods available in an Authlogic::Session::Base object that make up
      # the cookie feature set.
      module InstanceMethods
        # Allows you to set the remember_me option when passing credentials.
        def credentials=(value)
          super
          values = value.is_a?(Array) ? value : [value]
          case values.first
          when Hash
            if values.first.with_indifferent_access.key?(:remember_me)
              self.remember_me = values.first.with_indifferent_access[:remember_me]
            end
          else
            r = values.find { |val| val.is_a?(TrueClass) || val.is_a?(FalseClass) }
            self.remember_me = r unless r.nil?
          end
        end

        # Is the cookie going to expire after the session is over, or will it stick around?
        def remember_me
          return @remember_me if defined?(@remember_me)
          @remember_me = self.class.remember_me
        end

        # Accepts a boolean as a flag to remember the session or not. Basically
        # to expire the cookie at the end of the session or keep it for
        # "remember_me_until".
        def remember_me=(value)
          @remember_me = value
        end

        # See remember_me
        def remember_me?
          remember_me == true || remember_me == "true" || remember_me == "1"
        end

        # How long to remember the user if remember_me is true. This is based on the class
        # level configuration: remember_me_for
        def remember_me_for
          return unless remember_me?
          self.class.remember_me_for
        end

        # When to expire the cookie. See remember_me_for configuration option to change
        # this.
        def remember_me_until
          return unless remember_me?
          remember_me_for.from_now
        end

        # Has the cookie expired due to current time being greater than remember_me_until.
        def remember_me_expired?
          return unless remember_me?
          (Time.parse(cookie_credentials[2]) < Time.now)
        end

        # If the cookie should be marked as secure (SSL only)
        def secure
          return @secure if defined?(@secure)
          @secure = self.class.secure
        end

        # Accepts a boolean as to whether the cookie should be marked as secure.  If true
        # the cookie will only ever be sent over an SSL connection.
        def secure=(value)
          @secure = value
        end

        # See secure
        def secure?
          secure == true || secure == "true" || secure == "1"
        end

        # If the cookie should be marked as httponly (not accessible via javascript)
        def httponly
          return @httponly if defined?(@httponly)
          @httponly = self.class.httponly
        end

        # Accepts a boolean as to whether the cookie should be marked as
        # httponly.  If true, the cookie will not be accessible from javascript
        def httponly=(value)
          @httponly = value
        end

        # See httponly
        def httponly?
          httponly == true || httponly == "true" || httponly == "1"
        end

        # If the cookie should be marked as SameSite with 'Lax' or 'Strict' flag.
        def same_site
          return @same_site if defined?(@same_site)
          @same_site = self.class.same_site(nil)
        end

        # Accepts nil, 'Lax' or 'Strict' as possible flags.
        def same_site=(value)
          unless VALID_SAME_SITE_VALUES.include?(value)
            msg = "Invalid same_site value: #{value}. Valid: #{VALID_SAME_SITE_VALUES.inspect}"
            raise ArgumentError, msg
          end
          @same_site = value
        end

        # If the cookie should be signed
        def sign_cookie
          return @sign_cookie if defined?(@sign_cookie)
          @sign_cookie = self.class.sign_cookie
        end

        # Accepts a boolean as to whether the cookie should be signed.  If true
        # the cookie will be saved and verified using a signature.
        def sign_cookie=(value)
          @sign_cookie = value
        end

        # See sign_cookie
        def sign_cookie?
          sign_cookie == true || sign_cookie == "true" || sign_cookie == "1"
        end

        private

        def cookie_key
          build_key(self.class.cookie_key)
        end

        # Returns an array of cookie elements. See cookie format in
        # `generate_cookie_for_saving`. If no cookie is found, returns nil.
        def cookie_credentials
          cookie = cookie_jar[cookie_key]
          cookie&.split("::")
        end

        # The third element of the cookie indicates whether the user wanted
        # to be remembered (Actually, it's a timestamp, `remember_me_until`)
        # See cookie format in `generate_cookie_for_saving`.
        def cookie_credentials_remember_me?
          !cookie_credentials.nil? && !cookie_credentials[2].nil?
        end

        def cookie_jar
          if self.class.sign_cookie
            controller.cookies.signed
          else
            controller.cookies
          end
        end

        # Tries to validate the session from information in the cookie
        def persist_by_cookie
          persistence_token, record_id = cookie_credentials
          if persistence_token.present?
            record = search_for_record("find_by_#{klass.primary_key}", record_id)
            if record && record.persistence_token == persistence_token
              self.unauthorized_record = record
            end
            valid?
          else
            false
          end
        end

        def save_cookie
          if sign_cookie?
            controller.cookies.signed[cookie_key] = generate_cookie_for_saving
          else
            controller.cookies[cookie_key] = generate_cookie_for_saving
          end
        end

        def generate_cookie_for_saving
          value = format(
            "%s::%s%s",
            record.persistence_token,
            record.send(record.class.primary_key),
            remember_me? ? "::#{remember_me_until.iso8601}" : ""
          )
          {
            value: value,
            expires: remember_me_until,
            secure: secure,
            httponly: httponly,
            same_site: same_site,
            domain: controller.cookie_domain
          }
        end

        def destroy_cookie
          controller.cookies.delete cookie_key, domain: controller.cookie_domain
        end
      end
    end
  end
end
