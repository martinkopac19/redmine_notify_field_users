# frozen_string_literal: true

# Redmine Notify Field Users (Previo)
#
# Redmine natívne upozorní autora, riešiteľa a sledujúcich. Kto je zapísaný
# vo vlastnom poli typu "používateľ" (Tester, Project Manager, Code review,
# Idea owner, Design reviewer), sa o úlohe nedozvie nič — a práve tí ľudia
# majú s úlohou niečo urobiť.
#
# Plugin ich pridá medzi príjemcov notifikácií. Nahrádza mŕtvy plugin
# Restream/notify_custom_users (posledná zmena kódu 2016, hlási sa k Redmine 3.3
# a na 6.x nebeží — používa `alias_method_chain`, ktorý z Rails dávno vypadol).
#
# Žiadne migrácie, žiadny zásah do jadra: len `prepend` nad Issue a Journal.
require_relative 'lib/notify_field_users/issue_patch'
require_relative 'lib/notify_field_users/journal_patch'

Redmine::Plugin.register :redmine_notify_field_users do
  name 'Notify field users (Previo)'
  author 'Martin Kopáč'
  description 'Notifies people named in user-format custom fields (Tester, Project Manager, Code review…).'
  version '0.1.0'
  requires_redmine version_or_higher: '5.0'
  settings default: { 'enabled' => '1' }, partial: 'settings/notify_field_users'
end

# Patch je zámerne tu a nie v `to_prepare` — ten sa v production nespúšťa
# v správnom čase a patch by ticho nikdy nezabral (rovnaký vzor ako
# redmine_notification_filter a redmine_done_on_close).
unless Issue.ancestors.include?(NotifyFieldUsers::IssuePatch)
  Issue.prepend(NotifyFieldUsers::IssuePatch)
end
unless Journal.ancestors.include?(NotifyFieldUsers::JournalPatch)
  Journal.prepend(NotifyFieldUsers::JournalPatch)
end
