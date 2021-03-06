require 'test_helper'

class ReportImporterTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries = []
  end

  test 'json_fixture_loader' do
    assert_kind_of Hash, read_json_fixture('report-empty.json')
  end

  test 'it should import reports with no metrics' do
    r = TestReportImporter.import(read_json_fixture('report-empty.json'))
    assert r
    assert_equal({}, r.metrics)
  end

  test 'it should import reports where logs is nil' do
    r = Report.import read_json_fixture('report-no-logs.json')
    assert_empty r.logs
  end

  context 'with user owner' do
    setup do
      @owner = as_admin { FactoryGirl.create(:user, :admin, :with_mail) }
      @host = FactoryGirl.create(:host, :owner => @owner)
    end

    # Only ConfigReportImporter is set to send puppet error states
    test 'when owner is subscribed to notification, a mail should be sent on error' do
      @owner.mail_notifications << MailNotification[:puppet_error_state]
      assert_difference 'ActionMailer::Base.deliveries.size' do
        report = read_json_fixture('report-errors.json')
        report["host"] = @host.name
        ConfigReportImporter.import report
      end
    end

    test 'when owner is not subscribed to notifications, no mail should be sent on error' do
      @owner.mail_notifications = []
      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        report = read_json_fixture('report-errors.json')
        report["host"] = @host.name
        TestReportImporter.import report
      end
    end
  end

  test 'when a host has no owner, no mail should be sent on error' do
    host = FactoryGirl.create(:host, :owner => nil)
    report = read_json_fixture('report-errors.json')
    report["host"] = host.name
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      TestReportImporter.import report
    end
  end

  # Only ConfigReportImporter is set to send puppet error states
  test 'when usergroup owner is subscribed to notification, a mail should be sent to all users on error' do
    ug = FactoryGirl.create(:usergroup, :users => FactoryGirl.create_pair(:user, :with_mail))
    Usergroup.any_instance.expects(:recipients_for).with(:puppet_error_state).returns(ug.users)
    host = FactoryGirl.create(:host, :owner => ug)
    report = read_json_fixture('report-errors.json')
    report["host"] = host.name
    ConfigReportImporter.import report
    assert_equal ug.users.map { |u| u.mail }, ActionMailer::Base.deliveries.map { |d| d.to }.flatten
  end

  test 'if report has no error, no mail should be sent' do
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      TestReportImporter.import read_json_fixture('report-applied.json')
    end
  end

  test 'when a host does not exist, it builds a new one' do
    report = read_json_fixture('report-errors.json')
    report["host"] = 'SOMETHING'
    reporter = ReportImporter.new(report)
    host = reporter.send(:host)
    assert_equal 'something', host.name
  end

  test 'hostname is matched downcased' do
    db_host = FactoryGirl.create(:host)
    report = read_json_fixture('report-errors.json')
    report["host"] = db_host.name.upcase
    reporter = ReportImporter.new(report)
    host = reporter.send(:host)
    assert_equal host, db_host
  end
end

class TestReportImporter < ReportImporter
  def report_status
    0
  end
end
