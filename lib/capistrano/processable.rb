module Capistrano
  module Processable
    module SessionAssociation
      def self.on(exception, session)
        unless exception.respond_to?(:session)
          exception.extend(self)
          exception.session = session
        end

        return exception
      end

      attr_accessor :session
    end

    def process_iteration(wait=nil, &block)
      return false if block && !block.call(self)

      # NOTE: this used to replicate the logic in Net::SSH::Connection::Session#loop, but not fully correctly.
      # As a result, if you configured the SSH client to send keepalive packets, it wouldn't work
      # because it would just get stuck in the IO.select. What I'm doing instead is calling Net::SSH::Connection::Session#loop
      # until the session is no longer busy (default behaviour) and if there's a block present, that block returns false.
      # The block part is required for Capistrano::Transfer#process! to work correctly; otherwise, once the upload is complete,
      # it just stays stuck - it seems that Net::SSH::Connection::Session#busy? is not adequate here. My guess is that previously,
      # the IO.select loop would get triggered, and then it would re-enter this method and see that the block returns false.
      # Finally: previously, it would get the readers + writers for ALL the sessions and call IO.select on them. Now however,
      # ensure_each_session is called sequentially. I don't think we ever have multiple sessions with how we use capistrano,
      # but if we do, this might slow down a deployment or cause the loop to be stuck if the logic relies
      # on all sessions finishing. The solution might be to run each session in a thread and wait on them concurrently.
      return false unless sessions.any?
      ensure_each_session { |session| session.loop { session.busy? && (block.nil? || block.call(self)) } }

      return true
    end

    def ensure_each_session
      errors = []

      sessions.each do |session|
        begin
          yield session
        rescue Exception => error
          errors << SessionAssociation.on(error, session)
        end
      end

      raise errors.first if errors.any?
      sessions
    end
  end
end
