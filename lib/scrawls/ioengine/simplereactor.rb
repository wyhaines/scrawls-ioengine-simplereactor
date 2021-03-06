require 'scrawls/ioengine/simplereactor/version'
require 'scrawls/ioengine/base'
require 'socket'
require 'simplereactor'
require 'mime-types'

module Scrawls
  module Ioengine
    class Simplereactor < Scrawls::Ioengine::Base

      def initialize(scrawls)
        @scrawls = scrawls
      end

      def run( conf = {} )
        @config = conf
        ::SimpleReactor.use_engine @config[:reactor_engine].to_sym

        server = ::TCPServer.new( @config[:host], @config[:port] )

        fork_it( @config[:processes] - 1 )

        do_main_loop server
      end

      def fork_it( process_count )
        pid = nil
        process_count.times do
          if pid = fork
            Process.detach( pid )
          else
            break
          end
        end
      end

      def self.parse_command_line(configuration, meta_configuration)
        call_list = SimpleRubyWebServer::Config::TaskList.new

        configuration[:processes] = 1
        configuration[:reactor_engine] = :select
        meta_configuration[:helptext] << <<-EHELP
--processes COUNT:
  The number of processes to fork. Defaults to 1.

--reactor-engine ENGINE:
  The reactor engine to use within SimpleReactor. Unless otherwise specfied, the default is to attempt to use nio4r.

--threaded:
  Use events for IO, but run tasks in threads.
EHELP

        options = OptionParser.new do |opts|
          opts.on( '--processes COUNT' ) do |count|
            call_list << SimpleRubyWebServer::Config::Task.new(9000) { n = Integer( count.to_i ); n = n > 0 ? n : 1; configuration[:processes] = n }
          end

          opts.on( '--reactor-engine ENGINE' ) do |engine|
            call_list << SimpleRubyWebServer::Config::Task.new(9000) { configuration[:reactor_engine] = ( engine =~ /nio|select/ ) ? engine.to_sym : :select }
          end

          opts.on( '--threaded' ) do
            call_list << SimpleRubyWebServer::Config::Task.new(9000) { configuration[:threaded] = true }
          end
        end

        leftover_argv = []

        begin
          options.parse!(ARGV)
        rescue OptionParser::InvalidOption => e
          e.recover ARGV
          leftover_argv << ARGV.shift
          leftover_argv << ARGV.shift if ARGV.any? && ( ARGV.first[0..0] != '-' )
          retry
        end

        ARGV.replace( leftover_argv ) if leftover_argv.any?

        call_list
      end

      def do_main_loop server
        ::SimpleReactor.Reactor.run do |reactor|
          @reactor = reactor
          @reactor.attach server, :read do |monitor|
            @connection = monitor.io.accept
            get_request '',@connection, monitor
          end
        end 
      end

      def send_data data
        conn = ( Thread.current[:connection] || @connection )
        conn.write data unless conn.closed?
      end

      def close
        conn = ( Thread.current[:connection] || @connection )
        conn.flush
        conn.close
      end

      def get_request buffer, connection, monitor = nil
        eof = false
        buffer << connection.read_nonblock(16384)
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
        eof = true
      rescue IO::WaitReadable
        # This is actually handled in the logic below. We just need to survive it.
      ensure
        http_engine_instance = @scrawls.http_engine.new @scrawls
        http_engine_instance.receive_data buffer
        if !http_engine_instance.done? && monitor
          @reactor.next_tick do
            @reactor.attach connection, :read do |monitor|
              get_request buffer, connection
            end
          end
        elsif eof && !http_engine_instance.done?
          begin
            @scrawls.deliver_400 self
          rescue Errno::ECONNRESET, Errno::EPIPE, IOError
            @reactor.detach(connection)
            connection.close
          end
        elsif http_engine_instance.done?
          if @config[:threaded]
            Thread.new( connection ) do |conn|
              begin
                Thread.current[:connection] = conn
                handle http_engine_instance.env
                @reactor.next_tick do
                  @reactor.detach(connection)
                  connection.flush unless connection.closed?
                  connection.close
                end
              rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
                eof = true
              end
            end
          else
            begin
              handle http_engine_instance.env
            rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError
              eof = true
            end
          end
        end

        #if http_engine_instance.done? || eof
        if eof
          @reactor.next_tick do
            @reactor.detach(connection)
            connection.flush unless connection.closed?
            connection.close
          end
        end
      end

      def handle request
        if request
          @scrawls.process request, self
        else
          @scrawls.deliver_400 self
        end
      end

    end
  end
end
