# frozen_string_literal: true

# Regresný self-test pluginu redmine_notify_field_users.
#
# Spustenie (POZOR na `--user redmine`, inak zostanú v tmp/cache súbory patriace
# rootovi a aplikácia ich potom nedokáže prepísať):
#   docker compose exec -T --user redmine -e SECRET_KEY_BASE=<key> redmine \
#     bin/rails runner -e production plugins/redmine_notify_field_users/extra/selftest.rb
#
# Do databázy nič nezostane — všetko beží v transakcii, ktorá sa na konci zruší.
# Maily idú do :test kolektora, takže nikomu nič neodíde ani cez Mailpit.

require 'set'

OK = []
BAD = []
def check(label, got, want)
  ok = got == want
  (ok ? OK : BAD) << label
  puts format('  %-58s %s', label, ok ? 'OK' : "!! ZLE (#{got.inspect}, cakalo sa #{want.inspect})")
end

puts '=' * 78
puts '  notify_field_users selftest'
puts '=' * 78

field = IssueCustomField.where(field_format: 'user').order(:id).first
abort '  Ziadne pole formatu user — nie je co testovat.' if field.nil?
puts "\n[1] Prostredie"
puts "  testovane pole            : #{field.name} (id #{field.id})"
puts "  vsetky user polia         : #{IssueCustomField.where(field_format: 'user').pluck(:name).join(', ')}"
puts "  plugin zapnuty            : #{NotifyFieldUsers::Common.enabled?}"

original_delivery = ActionMailer::Base.delivery_method
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.deliveries.clear

ActiveRecord::Base.transaction do
  # --- príprava: úloha v projekte, kde je pole aktívne -----------------------
  project = Project.active.joins(:issue_custom_fields).where(custom_fields: { id: field.id }).first
  project ||= Project.active.first
  tracker = project.trackers.first
  author  = User.active.where(admin: true).first

  # dvaja ľudia, ktorí s úlohou inak nemajú nič spoločné
  candidates = User.active.where.not(id: author.id)
                   .where(mail_notification: %w[all selected only_my_events only_assigned])
                   .limit(30).to_a
  field_user = candidates.find { |u| u.allowed_to?(:view_issues, project) }
  next_user  = candidates.find { |u| u != field_user && u.allowed_to?(:view_issues, project) }
  if field_user.nil? || next_user.nil?
    puts "\n  !! V projekte #{project.name} sa nenasli dvaja pouzivatelia s pravom vidiet ulohy — test preskoceny."
    raise ActiveRecord::Rollback
  end

  puts "  projekt                   : #{project.name}"
  puts "  osoba v poli              : #{field_user.login} (##{field_user.id})"
  puts "  nahradnik                 : #{next_user.login} (##{next_user.id})"

  issue = Issue.new(project: project, tracker: tracker, author: author,
                    subject: '[selftest] notify_field_users', description: 'docasny task')
  issue.custom_field_values = { field.id.to_s => field_user.id.to_s }
  issue.save!(validate: false)

  # --- 2. zalozenie ulohy ----------------------------------------------------
  puts "\n[2] Zalozenie ulohy"
  recipients = issue.notified_users
  check('osoba v poli je medzi prijemcami', recipients.include?(field_user), true)

  # --- 3. zmena hodnoty pola -------------------------------------------------
  puts "\n[3] Zmena pola na ineho cloveka"
  # POZOR: `reload` NESTACI — `@current_journal` je memoizovany na instancii a reload
  # ho nezhodi, takze druhe ulozenie by recyklovalo prvy journal a obe zmeny by
  # skoncili v jednom zazname (na to tento test najprv naletel).
  issue = Issue.find(issue.id)
  issue.init_journal(author)
  issue.custom_field_values = { field.id.to_s => next_user.id.to_s }
  issue.save!(validate: false)
  journal = issue.journals.order(:id).last

  jr = journal.notified_users
  check('novy clovek dostane mail',           jr.include?(next_user),  true)
  check('odobraty clovek dostane mail',       jr.include?(field_user), true)

  # --- 4. bezna zmena bez dotyku pola ---------------------------------------
  puts "\n[4] Zmena stavu (pole ostava)"
  issue = Issue.find(issue.id)
  issue.init_journal(author)
  issue.subject = '[selftest] notify_field_users 2'
  issue.save!(validate: false)
  j2 = issue.journals.order(:id).last
  check('clovek v poli dostava aj bezne zmeny', j2.notified_users.include?(next_user), true)
  check('odobraty uz maily nedostava',          j2.notified_users.include?(field_user), false)

  # --- 5. kill-switch --------------------------------------------------------
  puts "\n[5] Vypinac v nastaveniach"
  old = Setting.plugin_redmine_notify_field_users
  Setting.plugin_redmine_notify_field_users = (old || {}).merge('enabled' => '0')
  issue = Issue.find(issue.id)
  check('s vypnutym pluginom sa nikto nepridava', issue.notified_users.include?(next_user), false)
  Setting.plugin_redmine_notify_field_users = old

  # --- 6. respektovanie "ziadne e-maily" -------------------------------------
  puts "\n[6] Pouzivatel s nastavenim ziadne e-maily"
  saved_pref = next_user.mail_notification
  next_user.update_columns(mail_notification: 'none')
  issue = Issue.find(issue.id)
  check('nedostane nic', issue.notified_users.include?(User.find(next_user.id)), false)
  next_user.update_columns(mail_notification: saved_pref)

  raise ActiveRecord::Rollback
end

ActionMailer::Base.deliveries.clear
ActionMailer::Base.delivery_method = original_delivery

puts "\n" + '=' * 78
puts "  OK: #{OK.size}   CHYBA: #{BAD.size}"
puts "  zostalo v DB: #{Issue.where(subject: ['[selftest] notify_field_users', '[selftest] notify_field_users 2']).count} testovacich uloh (ma byt 0)"
puts '=' * 78
