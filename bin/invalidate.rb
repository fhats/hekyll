#!/usr/bin/env ruby

require 'digest/md5'
require 'find'
require 'fog'
require 'optparse'
require 'yaml'

def invalidate_files(files, options)
	connection = Fog::CDN.new(
		:provider => "AWS",
		:aws_access_key_id => options[:aws_key],
		:aws_secret_access_key => options[:aws_secret]
	)

	fixed_paths = []
	files.each do|f|
		fixed_paths << "/#{f}"
	end

	connection.get_distribution(options[:cloudfront_dist])
	begin
		response = connection.post_invalidation(options[:cloudfront_dist], fixed_paths)
		if response.status < 200 or response.status > 299
			puts "Failed to post invalidation request!"
			puts response.body
			return false
		else
			puts "Invalidation ID: #{response.body['Id']}"
			return true
		end
	rescue => ex
		puts "Failed to post invalidation request!"
		puts "#{ex.response.status}"
		puts "#{ex.response.body}"
		return false
	end

end

options = {}
optparse = OptionParser.new do|opts|
	opts.banner = "Usage: invalidate.rb [options]"

	options[:aws_key] = ENV["AWS_KEY"]
	opts.on('-k', '--aws-key [KEY]', "AWS key to use") do|key|
		options[:aws_key] = key
	end

	options[:aws_secret] = ENV["AWS_SECRET"]
	opts.on('-s', '--aws-secret [SECRET]', 'AWS secret to use') do|secret|
		options[:aws_secret] = secret
	end

	options[:cache_dir] = ".cachestash"
	opts.on('-o', '--cache-dir [DIR]', "Dir to use to cache hashes") do|cachedir|
		options[:cache_dir] = cachedir
	end

	options[:cloudfront_dist] = ENV["CLOUDFRONT_DISTRIBUTION"]
	opts.on('-d', '--cf-dist [DIST]', "Cloudfront distribution to invalidate from") do|cf_dist|
		options[:cloudfront_dist] = cf_dist
	end

	options[:dry_run] = false
	opts.on('-n', '--dry-run', "Don't actually invalidate") do
		options[:dry_run] = true
	end

	options[:force] = false
	opts.on('-f', '--force', "Force invalidation") do
		options[:force] = true
	end

	options[:config_file] = "_config.yml"
	opts.on('-c', '--config [FILE]', "Config file") do|f|
		options[:config_file] = f
	end

	# This displays the help screen, all programs are
   	# assumed to have this option.
	opts.on( '-h', '--help', 'Display this screen' ) do
		puts opts
		exit
	end
end

optparse.parse!

config = YAML.load_file(options[:config_file])

# Make the cache stash if needed
if not FileTest::directory?(options[:cache_dir])
	Dir::mkdir(options[:cache_dir])
end

invalid_files = []

config['static_dirs'].each do|dir|
	Find.find(dir) do |f|
		next if /^\./.match(f)

		cachestash_f = File.join(options[:cache_dir], f)
		
		if FileTest::directory?(f)
			begin
				Dir::mkdir(cachestash_f)
			rescue
			end
			next
		end

		if not FileTest::file?(cachestash_f) or options[:force]
			invalid_files << f
		else
			begin
				current_hash = Digest::MD5.hexdigest(File.read(f))
			rescue
				puts "Error hashing #{f} -- invalidating..."
				current_hash = ""
			end

			previous_hash = File.read(cachestash_f)

			if current_hash != previous_hash
				invalid_files << f
			end
		end
	end
end

if invalid_files.length > 0
	puts "Invalidating..."

	invalidation_success = invalidate_files(invalid_files, options)

	if invalidation_success
		puts "Successfully invalidated!"

		invalid_files.each do|f|
			cachestash_f = File.join(options[:cache_dir], f)
			current_hash = Digest::MD5.hexdigest(File.read(f))

			File.open(cachestash_f, 'w+') do |of|
				of.write(current_hash)
			end
		end
	end
end