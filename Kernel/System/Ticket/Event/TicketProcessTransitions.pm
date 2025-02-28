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

package Kernel::System::Ticket::Event::TicketProcessTransitions;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::ProcessManagement::Process',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug} = 0;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Data Event Config UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # listen to all kinds of events
    if ( !$Param{Data}->{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketID in Data!",
        );
        return;
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $CacheKey = '_TicketProcessTransitions::AlreadyProcessed';

    # loop protection: only execute this handler once for each ticket, as multiple events may be
    #   fired, for example TicketTitleUpdate and TicketPriorityUpdate.
    return if ( $TicketObject->{$CacheKey}->{ $Param{Data}->{TicketID} } );

    # get ticket data in silent mode, it could be that the ticket was deleted
    #   in the meantime.
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Param{Data}->{TicketID},
        DynamicFields => 1,
        Silent        => 1,
    );

    if ( !%Ticket ) {

        # remember that the event was executed for this TicketID to avoid multiple executions.
        #   Store the information on the ticketobject
        $TicketObject->{$CacheKey}->{ $Param{Data}->{TicketID} } = 1;

        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $ProcessIDField  = $ConfigObject->Get("Process::DynamicFieldProcessManagementProcessID");
    my $ProcessEntityID = $Ticket{"DynamicField_$ProcessIDField"};

    my $ActivityIDField  = $ConfigObject->Get("Process::DynamicFieldProcessManagementActivityID");
    my $ActivityEntityID = $Ticket{"DynamicField_$ActivityIDField"};

    # ticket can be ignored if it is no process ticket. Don't set the cache key in this case as
    #   later events might make a transition check neccessary.
    return if ( !$ProcessEntityID || !$ActivityEntityID );

    # Ticket can be ignored if it does not belong to an active or fadeaway process.
    my $ProcessObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::Process');
    my $ProcessList   = $ProcessObject->ProcessList(
        ProcessState => [ 'Active', 'FadeAway' ],
        Interface    => 'all',
        Silent       => 1,
    );
    return if !$ProcessList->{$ProcessEntityID};

    # ok, now we know that we need to call the sequence flow logic for this ticket.

    # Remember that the event was executed for this ticket to avoid multiple executions.
    #   Store the information on the ticketobject, this needs to be done before the execution of the
    #   transitions as it could happen that the transition generates new events that will be
    #   processed in the mean time, before the chache is set, see bug#9748
    $TicketObject->{$CacheKey}->{ $Param{Data}->{TicketID} } = 1;

    my $TransitionApplied = $ProcessObject->ProcessTransition(
        ProcessEntityID  => $ProcessEntityID,
        ActivityEntityID => $ActivityEntityID,
        TicketID         => $Param{Data}->{TicketID},
        UserID           => $Param{UserID},
    );

    if ( $Self->{Debug} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  =>
                "Transition for to TicketID: $Param{Data}->{TicketID}"
                . "  ProcessEntityID: $ProcessEntityID OldActivityEntityID: $ActivityEntityID "
                . ( $TransitionApplied ? "was applied." : "was not applied." ),
        );
    }

    return 1;
}

1;
