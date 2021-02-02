module ActiveRecord
  class Migrator < ActiveRecord # :nodoc:
    class << self
      def generate_migrator_advisory_lock_id
        hash_input = ActiveRecord::Base.connection.current_database
        hash_input += ActiveRecord::Base.connection.current_schema if ActiveRecord::Base.connection.respond_to?(:current_schema)
        db_name_hash = Zlib.crc32(hash_input)
        MIGRATOR_SALT * db_name_hash
      end
    end
  end
end
