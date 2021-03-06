# The VCR test suite spawns a localhost webserver in a separate process, but it appears that
# heroku does not support this.  I'm using heroku for my CI server, so we disable these specs
# as pending specs when we're running on heroku.
module PendingOnHeroku
  if ENV.keys.include?('HEROKU_SLUG')
    def it(*args, &block)
      super description, *args do
        pending('pending on heroku because heroku does not allow the spawning of a localhost webserver') do
          instance_eval(&block)
        end
      end
    end
  end
end
