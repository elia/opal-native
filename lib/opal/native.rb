#--
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.
#++

class Module
	%x{
		function define_attr_bridge (klass, target, name, getter, setter) {
			if (getter) {
				$opal.defn(klass, $opal.mid_to_jsid(name), function() {
					var real_target = target;

					if (#{Symbol == target}) {
						real_target = target[0] == '@' ? this[target.substr(1)] : this[$opal.mid_to_jsid(target)].apply(this, null);
					}

					var result = real_target[name];

					return result == null ? nil : result;
				});
			}

			if (setter) {
				$opal.defn(klass, $opal.mid_to_jsid(name + '='), function (block, val) {
					var real_target = target;

					if (#{Symbol === target}) {
						real_target = target[0] == '@' ? this[target.substr(1)] : this[$opal.mid_to_jsid(target)].apply(this, null);
					}

					return real_target[name] = val;
				});
			}
		}
	}

	def attr_accessor_bridge (target, *attrs)
		%x{
			for (var i = 0, length = attrs.length; i < length; i++) {
				define_attr_bridge(this, target, attrs[i], true, true);
			}
		}

		self
	end

	def attr_reader_bridge (target, *attrs)
		%x{
			for (var i = 0, length = attrs.length; i < length; i++) {
				define_attr_bridge(this, target, attrs[i], true, false);
			}
		}

		self
	end

	def attr_writer_bridge (target, *attrs)
		%x{
			for (var i = 0, length = attrs.length; i < length; i++) {
				define_attr_bridge(this, target, attrs[i], false, true);
			}
		}

		self
	end

	def attr_bridge (target, name, setter = false)
		`define_attr_bridge(this, target, name, true, setter)`

		self
	end

	%x{
		function define_singleton_method_bridge (object, target, id, name) {
			$opal.defs(object, id, method_bridge_generator(target, name));
		}
	}

	def define_method_bridge (object, name, ali = nil)
		%x{
			$opal.defn(self, #{ali || name}, function () {
				if (#{Symbol === object}) {
					object = object[0] == '@' ? self[object.substr(1)] : this[$opal.mid_to_jsid(object)].apply(this);
				}

				return object[name].apply(object, arguments);
			});
		}

		nil
	end
end

module Kernel
	def define_singleton_method_bridge (object, name, ali = nil)
		%x{
			$opal.defs(self, #{ali || name}, function () {
				if (#{Symbol === object}) {
					object = object[0] == '@' ? self[object.substr(1)] : this[$opal.mid_to_jsid(object)].apply(this);
				}

				return object[name].apply(object, arguments);
			});
		}

		nil
	end
end

module Native
	def self.included (klass)
		class << klass
			def from_native (object)
				instance = allocate
				instance.instance_variable_set :@native, object

				instance
			end
		end
	end

	def initialize (native)
		@native = native
	end

	def to_native
		@native
	end

	def native_send (name, *args)
		return method_missing(name, *args) unless Opal.function? `#@native[name]`

		`#@native[name].apply(#@native, args)`
	end

	alias __native_send__ native_send
end

class Native::Object
	include Native
	include Enumerable

	def initialize (*)
		super

		update!
	end

	def update! (name = nil)
		unless name
			%x{
				for (var name in #@native) {
					#{update!(`name`)}
				}
			}

			return
		end

		if Opal.function? `#@native[name]`
			define_singleton_method_bridge @native, name

			if respond_to? "#{name}="
				class << self
					self
				end.undef_method "#{name}="
			end
		else
			class << self
				self
			end.attr_reader_bridge @native, name

			define_singleton_method "#{name}=" do |value|
				`#@native[name] = value`

				update!(name)
			end
		end
	end

	def each
		return enum_for :each unless block_given?

		%x{
			for (var name in #@native) {
				#{yield Object(`name`), Object(`#@native[name]`)}
			}
		}

		self
	end

	def each_key
		return enum_for :each_key unless block_given?

		%x{
			for (var name in #@native) {
				#{yield Object(`name`)}
			}
		}

		self
	end

	def each_value
		return enum_for :each_value unless block_given?

		%x{
			for (var name in #@native) {
				#{yield Object(`#@native[name]`)}
			}
		}
	end

	def [] (name)
		value = `#@native[name]`

		return if Opal.undefined? value

		Object(value)
	end

	def []= (name, value)
		value = value.to_native unless Opal.native?(value)

		`#@native[name] = #{value}`

		update!(name)

		value
	end

	def nil?
		`#@native === null || #@native === undefined`
	end

	def inspect
		"#<Native: #{`#@native.toString()`}>"
	end

	def to_s
		`#@native.toString()`
	end

	def to_hash
		Hash[to_a]
	end
end

class Object
	def to_native
		raise TypeError, 'no specialized #to_native has been implemented'
	end
end

class Boolean
	def to_native
		`self.valueOf()`
	end
end

class Array
	def to_native
		map { |obj| Opal.object?(obj) ? obj.to_native : obj }
	end
end

class Hash
	def to_native
		%x{
			var map    = this.map,
					result = {};

			for (var assoc in map) {
				var key   = map[assoc][0],
						value = map[assoc][1];

				result[key] = #{Opal.native?(`value`)} ? value : #{`value`.to_native};
			}

			return result;
		}
	end
end

class MatchData
	alias to_native to_a
end

class NilClass
	def to_native (result = undefined)
		result
	end
end

class Numeric
	def to_native
		`this.valueOf()`
	end
end

class Proc
	def to_native
		%x{
			return (function () {
				return self.apply(self.$S, arguments);
			});
		}
	end
end

class Regexp
	def to_native
		`this.valueOf()`
	end
end

class String
	def to_native
		`this.valueOf()`
	end
end

module Kernel
	def Object(object)
		Opal.native?(object) ? Native::Object.new(object) : object
	end
end
