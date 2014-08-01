require 'digest/sha1'

namespace :errbit do
  namespace :db do

    desc "Updates cached attributes on Problem"
    task :update_problem_attrs => :environment do
      puts "Updating problems"
      Problem.no_timeout.all.each do |problem|
        ProblemUpdaterCache.new(problem).update
      end
    end

    desc "Updates Problem#notices_count"
    task :update_notices_count => :environment do
      puts "Updating problem.notices_count"
      Problem.no_timeout.all.each do |pr|
        pr.update_attributes(:notices_count => pr.notices.count)
      end
    end

    desc "Delete resolved errors from the database. (Useful for limited heroku databases)"
    task :clear_resolved => :environment do
      require 'resolved_problem_clearer'
      puts "=== Cleared #{ResolvedProblemClearer.new.execute} resolved errors from the database."
    end

    desc "Regenerate fingerprints"
    task :regenerate_fingerprints => :environment do

      def normalize_backtrace(backtrace)
        backtrace[0...3].map do |trace|
          trace.merge 'method' => trace['method'].to_s.gsub(/[0-9_]{10,}+/, "__FRAGMENT__")
        end
      end

      def fingerprint(source)
        Digest::SHA1.hexdigest(source.to_s)
      end

      total = Notice.count.to_f
      done  = 0
      puts "Regenerating Err fingerprints for %d notices..." % [total]
      Err.create_indexes
      Notice.all.each do |notice|
        done += 1
        puts "%.0f%%" % [done / total] if (done % 1000 == 0)

        next unless notice.err.present? && notice.err.problem.present?

        fingerprint = ErrorReport.fingerprint_strategy.generate(notice, notice.app.api_key)
        notice.err = notice.app.find_or_create_err!(error_class: notice.error_class,
                                                    environment: notice.problem.environment,
                                                    fingerprint: fingerprint)
        notice.save
      end
      puts

      puts "Cleaning up defunct Errs"
      Err.all.each do |err|
        err.with(safe: {w: 0}).delete if err.notices.count == 0
      end
      puts

      puts "Cleaning up defunct Problems"
      Problem.all.each do |prob|
        prob.with(safe: {w: 0}).delete if prob.errs.count == 0
      end
      puts

      puts "All done!"
    end

    desc "Remove notices in batch"
    task :notices_delete, [ :problem_id ] => [ :environment ] do
      BATCH_SIZE = 1000
      if args[:problem_id]
        item_count = Problem.find(args[:problem_id]).notices.count
        removed_count = 0
        puts "Notices to remove: #{item_count}"
        while item_count > 0
          Problem.find(args[:problem_id]).notices.limit(BATCH_SIZE).each do |notice|
            notice.remove
            removed_count += 1
          end
          item_count -= BATCH_SIZE
          puts "Removed #{removed_count} notices"
        end
      end
    end
  end
end
