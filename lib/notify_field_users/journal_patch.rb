# frozen_string_literal: true

module NotifyFieldUsers
  # Pri úprave úlohy treba upozorniť aj toho, kto z poľa VYPADOL — inak sa
  # bývalý tester nikdy nedozvie, že úlohu už nemá na starosti. Aktuálnych ľudí
  # doplní IssuePatch (Journal#notified_users volá Issue#notified_users).
  module JournalPatch
    def notified_users
      base = super
      return base unless NotifyFieldUsers::Common.enabled?

      extra = NotifyFieldUsers::Common.extra_users(journalized, previous_field_user_ids)
      extra = filter_out_unwanted(extra)
      (base + extra).uniq
    rescue StandardError => e
      Rails.logger&.error("[notify_field_users] journal #{id}: #{e.class}: #{e.message}")
      base
    end

    private

    # Staré hodnoty polí typu "používateľ" z detailov tejto zmeny.
    # `property == 'cf'`, `prop_key` je id poľa, `old_value` id používateľa.
    def previous_field_user_ids
      return [] unless journalized.is_a?(Issue)

      field_ids = NotifyFieldUsers::Common.user_field_ids.map(&:to_s)
      details.select { |d| d.property == 'cf' && field_ids.include?(d.prop_key.to_s) }
             .map(&:old_value)
    end

    # Ak beží redmine_notification_filter, musí platiť aj na ľudí, ktorých sme
    # pridali my. Bez tohto by si človek nastavil „o zmenách stavu mi nepíš"
    # a od nás by ich aj tak dostával — jeho voľba by prestala platiť práve
    # v úlohách, kde je zapísaný ako tester.
    def filter_out_unwanted(users)
      return users unless defined?(::RedmineNotificationFilter::Filter)

      users.reject { |u| ::RedmineNotificationFilter::Filter.skip?(u, self) }
    rescue StandardError
      users
    end
  end
end
