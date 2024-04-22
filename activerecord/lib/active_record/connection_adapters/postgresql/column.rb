# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      class Column < ConnectionAdapters::Column # :nodoc:
        delegate :oid, :fmod, to: :sql_type_metadata

        def initialize(*, serial: nil, generated: nil, **)
          super
          @serial = serial
          @generated = generated
        end

        def serial?
          @serial
        end

        def virtual?
          # We assume every generated column is virtual, no matter the concrete type
          @generated.present?
        end

        def has_default?
          super && !virtual?
        end

        def array
          sql_type_metadata.sql_type.end_with?("[]")
        end
        alias :array? :array

        def sql_type
          super.sub(/\[\]\z/, "")
        end
      end
    end
    PostgreSQLColumn = PostgreSQL::Column # :nodoc:
  end
end
