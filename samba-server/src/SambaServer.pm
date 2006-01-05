# File:		modules/SambaServer.ycp
# Package:	Configuration of samba-server
# Summary:	Data for configuration of samba-server, input and output functions.
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#		Martin Lazar <mlazar@suse.cz>
#
# $Id$
#
# Representation of the configuration of samba-server.
# Input and output routines.


package SambaServer;

use strict;
use Switch 'Perl6';
use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-server";
our %TYPEINFO;

BEGIN {
YaST::YCP::Import("SCR");
YaST::YCP::Import("Mode");
YaST::YCP::Import("Report");
YaST::YCP::Import("Summary");
YaST::YCP::Import("Progress");
#HELPME: YaST::YCP::Import("Directory");
YaST::YCP::Import("SuSEFirewall");
YaST::YCP::Import("PackageSystem");

YaST::YCP::Import("SambaRole");
YaST::YCP::Import("SambaConfig");
YaST::YCP::Import("SambaService");
YaST::YCP::Import("SambaBackend");
YaST::YCP::Import("SambaSecrets");
YaST::YCP::Import("SambaNmbLookup");
YaST::YCP::Import("SambaTrustDom");
YaST::YCP::Import("SambaAccounts");
}

use constant {
#HELPME:    DONE_ONCE_FILE => Directory->vardir . "/samba_server_done_once"
    DONE_ONCE_FILE => "/var/lib/YaST2" . "/samba_server_done_once"
};


my $Modified;

# list of required packages
my $RequiredPackages = ["samba", "samba-client"];

my $GlobalsConfigured = 0;


# Set modify flag
BEGIN{ $TYPEINFO{SetModified} = ["function", "void"] }
sub SetModified {
    my ($self) = @_;
    $Modified = 1;
}

# Data was modified?
BEGIN{ $TYPEINFO{GetModified} = ["function", "boolean"] }
sub GetModified {
    my ($self) = @_;
    return $Modified 
	|| SambaConfig->GetModified() 
	|| SambaService->GetModified() 
	|| SambaBackend->GetModified()
	|| SambaTrustDom->GetModified()
	|| SambaAccounts->GetModified();
};

# Read all samba-server settings
# @param force_reread force reread configuration
# @param no_progreass_bar disable progress bar
# @return true on success
BEGIN{ $TYPEINFO{Read} = ["function", "boolean"] }
sub Read {
    my ($self) = @_;

    # Samba-server read dialog caption
    my $caption = __("Initializing Samba Server Configuration");

    # We do not set help text here, because it was set outside
    Progress->New($caption, " ", 6, [
	    # translators: progress stage 1/6
	    __("Read global Samba settings"),
	    # translators: progress stage 2/6
	    __("Read Samba secrets"),
	    # translators: progress stage 3/6
	    __("Read Samba service settings"),
	    # translators: progress stage 4/6
	    __("Read Samba accounts"),
	    # translators: progress stage 5/6
	    __("Read the back-end settings"),
	    # translators: progress stage 6/6
	    __("Read the firewall settings")
	], [
	    # translators: progress step 1/6
	    __("Reading global Samba settings..."),
	    # translators: progress step 2/6
	    __("Reading Samba secrets..."),
	    # translators: progress step 3/6
	    __("Reading Samba service settings..."),
	    # translators: progress step 4/6
	    __("Reading Samba accounts..."),
	    # translators: progress step 5/6
	    __("Reading the back-end settings..."),
	    # translators: progress step 6/6
	    __("Reading the firewall settings..."),
	    # translators: progress finished
	    __("Finished")
	],
	""
    );

    # 1: read global settings
    Progress->NextStage();
    # check installed packages
    unless (Mode->test()) {
	PackageSystem->CheckAndInstallPackagesInteractive($RequiredPackages) or return 0;
    }
    SambaConfig->Read();
    
    # 2: read samba secrets
    Progress->NextStage();
    SambaSecrets->Read();
    
    # 3: read services settings
    Progress->NextStage();
    SambaService->Read();
    # start nmbstatus in background
    SambaNmbLookup->Start() unless Mode->test();
    
    # 4: read accounts
    Progress->NextStage();
    SambaAccounts->Read();

    # 5: read backends settings
    Progress->NextStage();
    SambaBackend->Read();

    # 6: read firewall setting
    Progress->NextStage();
    my $po = Progress->set(0);
    SuSEFirewall->Read();
    Progress->set($po);
#    if(Abort()) return false;

    # Read finished
    Progress->NextStage();
    $Modified = 0;

    $GlobalsConfigured = $self->Configured();

    y2milestone("Service:". (SambaService->GetServiceAutoStart() ? "Enabled" : "Disabled"));
    y2milestone("Role:". SambaRole->GetRoleName());
    
    return 1;
}

BEGIN{ $TYPEINFO{Configured} = ["function", "boolean"] }
sub Configured {
    my ($self) = @_;

    # check /etc/samba/smb.conf
    return 0 unless SambaConfig->Configured();
    
    # check file /$VARDIR/samba_server_done_once
    my $stat = SCR->Read(".target.stat", DONE_ONCE_FILE);
    return 1 if defined $stat->{size};

    # check if the main config file is modified already
    my $res = SCR->Execute(".target.bash_output", "rpm -V samba-client | grep '/etc/samba/smb\.conf'");
    return 1 if $res && !$res->{"exit"} and $res->{"stdout"};

    return 0;
}


# Write all samba-server settings
# @param write_only if true write only
# @return true on success
BEGIN{ $TYPEINFO{Write} = ["function", "boolean", "boolean"] }
sub Write {
    my ($self, $write_only) = @_;

    # Samba-server read dialog caption
    my $caption = __("Saving Samba Server Configuration");

    # We do not set help text here, because it was set outside
    Progress->New($caption, " ", 5, [
	    # translators: write progress stage
	    _("Write global settings"),
	    # translators: write progress stage
	    ( !SambaService->GetServiceAutoStart() ? _("Disable Samba services") 
	    # translators: write progress stage
		: _("Enable Samba services") ),
	    # translators: write progress stage
	    _("Write back-end settings"),
	    # translators: write progress stage
	    _("Write Samba accounts"),
	    # translators: write progress stage
	    _("Save firewall settings")
	], [
	    # translators: write progress step
	    _("Writing global settings..."),
	    # translators: write progress step
	    ! SambaService->GetServiceAutoStart() ? _("Disabling Samba services...") 
	    # translators: write progress step
		: _("Enabling Samba services..."),
	    # translators: write progress step
	    _("Writing back-end settings..."),
	    # translators: write progress step
	    _("Writing Samba accounts..."),
	    # translators: write progress step
	    _("Saving firewall settings..."),
	    # translators: write progress step
	    _("Finished")
	],
	""
    );

    # 1: write settings
    # if nothing to write, quit (but show at least the progress bar :-)
    Progress->NextStage();
    return 1 unless $self->GetModified();

    # check, if we need samba-pdb package
    my %backends = map {/:/;$`||$_,1} split " ", SambaConfig->GlobalGetStr("passdb backend", "");
    if($backends{mysql}) {
	PackageSystem->CheckAndInstallPackagesInteractive(["samba-pdb"]) or return 0;
    }
    if (!SambaConfig->Write($write_only)) {
	# /etc/samba/smb.conf is filename
    	Report->Error(__("Cannot write settings to /etc/samba/smb.conf."));
	return 0;
    }
    SCR->Execute(".target.bash", "touch " . DONE_ONCE_FILE);
    
    # 2: write services settings
    Progress->NextStage();
    SambaService->Write();

    # 3: write backends settings && write trusted domains
    Progress->NextStage();
    SambaBackend->Write();
    SambaTrustDom->Write();
    
    # 4: write accounts
    Progress->NextStage();
    SambaAccounts->Write();

    # 4.5: start, stop, reload service
    SambaService->StartStopReload();

    # 5: save firewall settings
    Progress->NextStage();
    my $po = Progress->set(0);
    SuSEFirewall->Write();
    Progress->set($po);
    
    # progress finished
    Progress->NextStage();

    $GlobalsConfigured = 1;
    $Modified = 0;

    return 1;
}

# Get all samba-server settings from the first parameter
# (For use by autoinstallation.)
# @param settings The YCP structure to be imported.
BEGIN{ $TYPEINFO{Import} = ["function", "void", ["map", "any", "any"]] }
sub Import {
    my ($self, $settings) = @_;

    if ($settings and $settings->{"config"} and keys %{$settings->{"config"}}) {
	$GlobalsConfigured = 1;
    } else {
	$GlobalsConfigured = 0;
    }
    $Modified = 0;
	
    y2debug("Importing: ", Dumper($settings));

    SambaConfig->Import($settings->{"config"});
    SambaService->Import($settings->{"service"});
    SambaTrustDom->Import($settings->{"trustdom"});
    SambaBackend->Import($settings->{"backend"});
    SambaAccounts->Import($settings->{"accounts"});
}

# Dump the samba-server settings to a single map
# (For use by autoinstallation.)
# @return map Dumped settings (later acceptable by Import ())
BEGIN{ $TYPEINFO{Export} = ["function", "any"]}
sub Export {
    my ($self) = @_;

    $GlobalsConfigured = 1 if $self->GetModified();
    $Modified = 0;
    
    return {
	version =>	"2.11",
	config =>	SambaConfig->Export(),
	backend =>	SambaBackend->Export(),
	service =>	SambaService->Export(),
	trustdom =>	SambaTrustDom->Export(),
	accounts =>	SambaAccounts->Export(),
    };
}

# Create a textual summary and a list of unconfigured options
# @return summary of the current configuration
BEGIN { $TYPEINFO{Summary} = ["function", "string"] }
sub Summary {
    my ($self) = @_;
    
    # summary header
    my $summary = "";
    
    unless ($GlobalsConfigured) {
	$summary = Summary->AddLine($summary, Summary->NotConfigured());
	return $summary;
    }
    
    # summary item: configured workgroup/domain
    $summary = Summary->AddHeader($summary, __("Global Configuration:"));
    
    $summary = Summary->AddLine($summary, sprintf(__("Workgroup or Domain: %s"), SambaConfig->GlobalGetStr("workgroup", "")));

    if (SambaService->GetServiceAutoStart()) {
        # summary item: selected role for the samba server
        $summary = Summary->AddLine($summary, sprintf(__("Role: %s"), SambaRole->GetRoleName()));
    } else {
        # summary item: status of the samba service
        $summary = Summary->AddLine($summary, __("Samba server is disabled"));
    }

    # summary heading: configured shares
    $summary = Summary->AddHeader($summary, __("Share Configuration:"));

    my $shares = SambaConfig->GetShares();
    
    if (!$shares or $#$shares<0) {
        # summary item: no configured shares
        $summary = Summary->AddLine($summary, __("None"));
    } else {
	$summary = Summary->OpenList($summary);
    	foreach(@$shares) {
	    my $path = SambaConfig->ShareGetStr($_, "path", undef);
	    $summary = Summary->AddListItem($summary, $_ . ($path ? " (<i>$path</i>)" : ""));
	
	    my $comment = SambaConfig->ShareGetComment($_);
    	    $summary = Summary->AddLine($summary, $comment) if $comment;
	};
	$summary = Summary->CloseList($summary);
    }

    return $summary;
}

# Return required packages for auto-installation
# @return map of packages to be installed and to be removed
BEGIN{$TYPEINFO{AutoPackages}=["function",["map","string",["list","string"]]]}
sub AutoPackages {
    my ($self) = @_;
    return { install=> $RequiredPackages, remove => []};
}

8;
