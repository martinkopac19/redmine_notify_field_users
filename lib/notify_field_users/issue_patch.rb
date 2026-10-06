# frozen_string_literal: true

module NotifyFieldUsers
  # Spoločná logika: kto je v poliach typu "používateľ" a smie mu prísť mail.
  module Common
    module_function

    def enabled?
      Setting.plugin_redmine_notify_field_users.presence&.[]('enabled').to_s != '0'
    end

    # Id všetkých issue polí formátu "user". Zámerne sa NEkonfiguruje zoznam —
    # keď niekto založí nové pole tohto typu, má fungovať rovnako ako Tester.
    #
    # Bez cache: `RequestStore` v tejto inštancii nie je a vlastná cache by pri
    # pridaní poľa držala zastaraný zoznam. Je to jeden index scan nad tabuľkou
    # s desiatkami riadkov, a volá sa len keď sa naozaj posiela notifikácia.
    def user_field_ids
      IssueCustomField.where(field_format: 'user').pluck(:id)
    end

    # Používatelia zapísaní v týchto poliach práve teraz.
    def current_users(issue)
      ids = issue.custom_field_values.select { |v| v.custom_field.field_format == 'user' }
                 .flat_map { |v| Array(v.value) }
                 .reject(&:blank?)
      users_for(ids)
    end

    def users_for(ids)
      ids = Array(ids).flatten.reject(&:blank?).map(&:to_s).uniq
      return [] if ids.empty?

      User.where(id: ids).to_a
    end

    # Smie tomuto človeku prísť mail o tejto úlohe?
    #
    # Rešpektuje sa jediné nastavenie: „žiadne e-maily" (mail_notification 'none')
    # a zamknuté účty. Ostatné voľby (napr. „len úlohy, kde som riešiteľ") sa
    # ZÁMERNE prebíjajú — zápis do poľa Tester je adresné poverenie rovnako ako
    # priradenie úlohy, a keby ho tieto voľby odfiltrovali, plugin by u polovice
    # ľudí ticho nerobil nič. Kto maily nechce vôbec, ten ich nedostane.
    def notifiable?(user, issue)
      user.is_a?(User) && user.active? &&
        user.mail_notification.to_s != 'none' &&
        issue.visible?(user)
    end

    def extra_users(issue, ids)
      users_for(ids).select { |u| notifiable?(u, issue) }
    end
  end

  # Pokrýva založenie úlohy (Mailer.deliver_issue_add) aj základ pre úpravy —
  # Journal#notified_users volá práve toto.
  module IssuePatch
    def notified_users
      base = super
      return base unless NotifyFieldUsers::Common.enabled?

      extra = NotifyFieldUsers::Common.current_users(self)
                                      .select { |u| NotifyFieldUsers::Common.notifiable?(u, self) }
      (base + filter_out_unwanted(extra)).uniq
    rescue StandardError => e
      # Notifikácia nikdy nesmie zhodiť uloženie úlohy.
      Rails.logger&.error("[notify_field_users] issue #{id}: #{e.class}: #{e.message}")
      base
    end

    private

    # Režim „Only mentions" z redmine_notification_filter musí platiť aj na ľudí, ktorých
    # pridávame my — inak by tester dostal mail o novej úlohe, hoci chce len @zmienky.
    # (Pre úpravy to rieši JournalPatch#filter_out_unwanted.)
    def filter_out_unwanted(users)
      filter = defined?(::RedmineNotificationFilter::Filter) && ::RedmineNotificationFilter::Filter
      return users unless filter && filter.respond_to?(:skip_issue_add?)

      users.reject { |u| filter.skip_issue_add?(u, self) }
    rescue StandardError
      users
    end
  end
end
