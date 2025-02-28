# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2023 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use v5.24;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterDriver;    # Set up $Self and $Kernel::OM
use Kernel::System::UnitTest::Selenium;

our $Self;

my $Selenium = Kernel::System::UnitTest::Selenium->new( LogExecuteCommandActive => 1 );

$Selenium->RunTest(
    sub {

        my $Helper        = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
        my $SLAObject     = $Kernel::OM->Get('Kernel::System::SLA');

        my $Config = {

            # Service data
            Services => [
                { Name => "TestService - " . $Helper->GetRandomID() },
                { Name => "TestService - " . $Helper->GetRandomID() },
            ],

            # SLA data
            SLAs => [
                {
                    Name => "TestSLA - " . $Helper->GetRandomID(),
                },
                {
                    Name => "TestSLA - " . $Helper->GetRandomID(),
                },
            ],
        };

        my $Success = $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 1,
        );

        # Add Services.
        my @ServiceIDs;
        my %ServicesNameToID;
        SERVICE:
        for my $Service ( @{ $Config->{Services} } ) {

            next SERVICE if !$Service;
            next SERVICE if !%{$Service};

            my $ServiceID = $ServiceObject->ServiceAdd(
                %{$Service},
                ValidID => 1,
                UserID  => 1,
            );

            $Self->True(
                $ServiceID,
                "Service $ServiceID has been created."
            );

            # Add service as default service for all customers.
            $ServiceObject->CustomerUserServiceMemberAdd(
                CustomerUserLogin => '<DEFAULT>',
                ServiceID         => $ServiceID,
                Active            => 1,
                UserID            => 1,
            );

            push @ServiceIDs, $ServiceID;
        }

        # Add SLAs and connect them with the Services.
        my @SLAIDs;
        SLA:
        for my $SLA ( @{ $Config->{SLAs} } ) {

            next SLA if !$SLA;
            next SLA if !%{$SLA};

            my $SLAID = $SLAObject->SLAAdd(
                %{$SLA},
                ValidID => 1,
                UserID  => 1,
            );

            $Self->True(
                $SLAID,
                "SLA $SLAID has been created."
            );

            push @SLAIDs, $SLAID;
        }

        # Create test user and login.
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users', 'stats' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentStatistics;Subaction=Import");

        # Import test selenium statistic.
        my $LocationNotExistingObject = $ConfigObject->Get('Home')
            . "/scripts/test/sample/Stats/Stats.Static.NotExisting.xml";
        $Selenium->find_element( "#File", 'css' )->send_keys($LocationNotExistingObject);

        $Selenium->find_element("//button[\@value='Import'][\@type='submit']")->click();
        $Selenium->WaitFor(
            JavaScript => "return typeof(\$) === 'function' && \$('.Dialog.Modal #DialogButton1').length;"
        );

        # Confirm JS error.
        $Selenium->find_element( "#DialogButton1", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return !\$('.Dialog.Modal').length;" );

        # Verify error class.
        $Self->Is(
            $Selenium->execute_script(
                "return \$('#File.Error').length;"
            ),
            '1',
            'Import file field has class error',
        );

        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentStatistics;Subaction=Import");

        # Import test selenium statistic.
        my $Location = $ConfigObject->Get('Home')
            . "/scripts/test/sample/Stats/Stats.TicketOverview.de.xml";
        $Selenium->find_element( "#File", 'css' )->send_keys($Location);

        $Selenium->find_element("//button[\@value='Import'][\@type='submit']")->VerifiedClick();

        # Create params for import test stats.
        my %StatsValues = (
            Title       => 'Überblick über alle Tickets im System',
            Object      => 'Ticket',
            Description => 'Aktueller Status aller im System befindlicher Tickets ohne Zeitbeschränkung.',
            Format      => 'D3::BarChart',
        );

        # Check for imported values on test stat.
        for my $StatsValue ( sort keys %StatsValues ) {
            ok(
                index( $Selenium->get_page_source(), $StatsValues{$StatsValue} ) > -1,
                "expected param $StatsValue for imported stat is found - $StatsValues{$StatsValue}"
            );
        }

        # Navigate to AgentStatistics Overview screen.
        $Selenium->VerifiedGet(
            "${ScriptAlias}index.pl?Action=AgentStatistics;Subaction=Overview;Direction=DESC;OrderBy=ID;StartHit=1;"
        );

        my $StatsObject = $Kernel::OM->Get('Kernel::System::Stats');

        # Get stats IDs.
        my $StatsIDs = $StatsObject->GetStatsList(
            AccessRw => 1,
            UserID   => 1,
        );

        my $Count       = scalar @{$StatsIDs};
        my $StatsIDLast = $StatsIDs->[ $Count - 1 ];

        # Check for imported stats on overview screen.
        $Self->True(
            index( $Selenium->get_page_source(), $StatsValues{Title} ) > -1,
            "Imported stat $StatsValues{Title} - found on overview screen"
        );

        # Go to imported stat to run it.
        $Selenium->find_element("//a[contains(\@href, \'AgentStatistics;Subaction=Edit;StatID=$StatsIDLast\' )]")
            ->VerifiedClick();

        # Change preview format to Print.
        $Selenium->find_element("//button[contains(\@data-format, \'Print')]")->click();
        $Selenium->WaitFor(
            JavaScript => "return typeof(\$) === 'function' && \$('#PreviewContentPrint:visible').length;"
        );

        $Self->True(
            $Selenium->execute_script("return \$('#PreviewContentPrint').css('display')") eq 'block',
            "Print format is displayed",
        );
        $Self->True(
            $Selenium->execute_script("return \$('#PreviewContentD3BarChart').css('display')") eq 'none',
            "Bar format is not displayed",
        );

        # Change preview format to Bar.
        $Selenium->find_element("//button[contains(\@data-format, \'D3::BarChart')]")->click();
        $Selenium->WaitFor(
            JavaScript => "return typeof(\$) === 'function' && \$('#PreviewContentD3BarChart:visible').length;"
        );

        $Self->True(
            $Selenium->execute_script("return \$('#PreviewContentD3BarChart').css('display');") eq 'block',
            "Bar format is displayed",
        );
        $Self->True(
            $Selenium->execute_script("return \$('#PreviewContentPrint').css('display')") eq 'none',
            "Print format is not displayed",
        );

        # Toggle General Specification.
        $Selenium->find_element("//a[contains(\@aria-controls, \'Core_UI_AutogeneratedID_0')]")->click();
        $Selenium->WaitFor(
            JavaScript =>
                "return typeof(\$) === 'function' && \$('.WidgetSimple:contains(General Specification).Expanded').length;"
        );
        $Selenium->find_element( "#Title", 'css' )->send_keys(" - Updated");

        # Check X-axis configuration dialog.
        $Selenium->find_element( ".EditXAxis", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return \$('.Dialog.Modal #EditDialog a.RemoveButton i').length;" );

        $Selenium->find_element( "#EditDialog a.RemoveButton i", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return \$('.Dialog.Modal #EditDialog .TableLike.Add:visible').length;" );

        $Selenium->InputFieldValueSet(
            Element => '#EditDialog select',
            Value   => 'XAxisServiceIDs',
        );
        $Selenium->find_element( "#DialogButton1", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return !\$('.Dialog.Modal').length;" );

        # Check Y-axis configuration dialog.
        $Selenium->find_element( ".EditYAxis", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return \$('.Dialog.Modal #EditDialog a.RemoveButton i').length;" );

        $Selenium->find_element( "#EditDialog a.RemoveButton i", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return \$('.Dialog.Modal #EditDialog .TableLike.Add:visible').length;" );

        $Selenium->InputFieldValueSet(
            Element => '#EditDialog select',
            Value   => 'YAxisSLAIDs',
        );
        $Selenium->find_element( "#DialogButton1", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return !\$('.Dialog.Modal').length;" );

        # Check Restrictions configuration dialog.
        $Selenium->find_element("//span[contains(.,\'Filter\')]")->click();
        $Selenium->WaitFor( JavaScript => "return \$('.Dialog.Modal').length;" );
        $Selenium->WaitFor( JavaScript => "return \$('#EditDialog select').length;" );

        $Selenium->InputFieldValueSet(
            Element => '#EditDialog select',
            Value   => 'RestrictionsQueueIDs',
        );

        # Wait for load selected Restriction - QueueIDs.
        $Selenium->WaitFor( JavaScript => 'return $("#RestrictionsQueueIDs").length;' );

        # Add restriction per Queue - Junk.
        $Selenium->InputFieldValueSet(
            Element => '#EditDialog #RestrictionsQueueIDs',
            Value   => 3,
        );
        $Selenium->find_element( "#DialogButton1", 'css' )->click();
        $Selenium->WaitFor( JavaScript => "return !\$('.Dialog.Modal').length;" );

        # Save and finish edit.
        $Selenium->find_element("//button[\@name='SaveAndFinish'][\@type='submit']")->VerifiedClick();

        # Sort decreasing by StatsID.
        $Selenium->VerifiedGet(
            "${ScriptAlias}index.pl?Action=AgentStatistics;Subaction=Overview;Direction=DESC;OrderBy=ID;StartHit=1"
        );

        # Delete imported test stats.
        $Selenium->find_element(
            "//a[contains(\@href, \'Action=AgentStatistics;Subaction=DeleteAction;StatID=$StatsIDLast\')]"
        )->click();

        $Selenium->WaitFor( AlertPresent => 1 );
        $Selenium->accept_alert();

        $Selenium->WaitFor(
            JavaScript =>
                'return typeof(Core) == "object" && typeof(Core.App) == "object" && Core.App.PageLoadComplete;'
        );
        $Selenium->WaitFor(
            JavaScript =>
                "return typeof(\$) === 'function' && !\$('a[href*=\"Action=AgentStatistics;Subaction=Edit;StatID=$StatsIDLast\"]').length;"
        );

        $Self->True(
            index( $Selenium->get_page_source(), "Action=AgentStatistics;Subaction=Edit;StatID=$StatsIDLast" ) == -1,
            "Test statistic is deleted - $StatsIDLast "
        );

        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

        # Clean up test data.
        for my $SLAID (@SLAIDs) {
            my $Success = $DBObject->Do(
                SQL => "DELETE FROM service_sla WHERE sla_id = $SLAID",
            );
            $Self->True(
                $Success,
                "ServiceSla - $SLAID",
            );

            $Success = $DBObject->Do(
                SQL => "DELETE FROM sla WHERE id = $SLAID",
            );
            $Self->True(
                $Success,
                "SLADelete - $SLAID",
            );
        }

        for my $ServiceID (@ServiceIDs) {
            my $Success = $DBObject->Do(
                SQL => "DELETE FROM service_customer_user WHERE service_id = $ServiceID",
            );
            $Self->True(
                $Success,
                "ServiceCustomerUser deleted - $ServiceID",
            );

            $Success = $DBObject->Do(
                SQL => "DELETE FROM service WHERE id = $ServiceID",
            );
            $Self->True(
                $Success,
                "Deleted Service - $ServiceID",
            );
        }

        my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

        # Make sure the cache is correct.
        for my $Cache (qw(Service SLA Stats)) {
            $CacheObject->CleanUp( Type => $Cache );
        }
    }
);

done_testing();
