#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  check_sun_cluster.pl
#
#        USAGE:  ./check_sun_cluster.pl  
#
#  DESCRIPTION:  Check SUN Cluster status on the current host  
#
#      OPTIONS:  [-b scstat_binary] [-n] [-w] [-q] [-i] [-a] [-h]
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pierre Mavro (), pierre@mavro.fr
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  17/12/2009 16:35:52
#     REVISION:  ---
#===============================================================================
#
# v0.1 :
# + First version
#
#===============================================================================

use strict;
no strict "refs";
use warnings;
use Getopt::Long;
use Sys::Hostname;

# Command Args
sub check_opts
{
	# Vars
	my ($node,$wwn,$quorum,$ipmp,$all);
	my $scstat_binary = '/usr/cluster/bin/scstat';
	
	# Set options
	GetOptions( "help|h"    => \&help,
				"b=s"		=> \$scstat_binary,
				"n" 	    => \$node,
				"w"			=> \$wwn,
				"q"			=> \$quorum,
				"i"			=> \$ipmp,
				"a"			=> \$all);
				
	unless (($node) or ($wwn) or ($quorum) or ($ipmp) or ($all))
	{
		&help;
	}
	else
	{
		my (@errors, $get_error, $function_name);
		
		# Get hostname
		my $hostname=hostname;
		
		sub check_with_return_vars
		{
			my $get_error;
			my $scstat_binary=shift;
			my $all = shift;
			my $function_name = shift;
			my $hostname = shift;
			my $current_check=shift;
			
			if(($current_check) or ($all))
			{
				$get_error = &$function_name($scstat_binary,$hostname);
				if ($get_error ne '0')
				{
					return $get_error;
				}
			}
			return 0;
		}
		
		# Check node status
		$get_error = &check_with_return_vars($scstat_binary,$all,'check_node',$hostname,$node);
		push @errors, $get_error if ($get_error ne '0');

		# Check Transport Path
		if (($wwn) or ($all))
		{
			$get_error = &check_transport_path($scstat_binary,$hostname);
			if ($get_error ne '0')
			{
				my @current_errors = @$get_error;
				foreach (@current_errors)
				{
					push @errors, $_;
				}
			}
		}

    	# Check quorum
    	$get_error = &check_with_return_vars($scstat_binary,$all,'check_quorum',$hostname,$quorum);
		push @errors, $get_error if ($get_error ne '0');
		
		# Check IPMP
		$get_error = &check_with_return_vars($scstat_binary,$all,'check_ipmp',$hostname,$ipmp);
		push @errors, $get_error if ($get_error ne '0');
		
		&send_to_nagios(\@errors);
	}
}

# Help print
sub help
{
    print "Usage : ./check_sun_cluster.pl [-b scstat_binary] [-n] [-w] [-q] [-i] [-a] [-h]\n";
    print "\t-n : Check if this server is a cluster's member\n";
    print "\t-w : Check transport paths are online\n";
    print "\t-q : Check if quorum is online\n";
    print "\t-i : Check IPMP status\n";
    print "\t-a : Check everythings\n";
    print "\t-h : Print this help message\n";
    exit 1;
}

# Check node status
sub check_node
{
	my $scstat_binary=shift;
	my $hostname=shift;
	
	open (NODE_STATUS, "$scstat_binary -n |");
	while (<NODE_STATUS>)
	{
		chomp $_;
		if (/(Cluster node:\s*$hostname\s*(\w*))/)
		{
			if ($2 !~ /Online/i)
			{
				return $1;
			}
			else
			{
				return 0;
			}
		}
	}
	close(NODE_STATUS);
	return "$hostname is missing in the available cluster nodes";
}

# Check Transport Path
sub check_transport_path
{
	my $scstat_binary=shift;
	my $hostname=shift;
	my $wwn_found=0;
	my @errors;
	
	open (NODE_STATUS, "$scstat_binary -W |");
	while (<NODE_STATUS>)
	{
		chomp $_;
		if ((/(Transport path:\s*$hostname:.*Path (\w+))/) or (/(Transport path:\s*\S*:\S*\s*$hostname:.*Path (\w+))/))
		{
			if ($2 !~ /online/i)
			{
				push @errors, $1;
			}
			else
			{
				$wwn_found=1;
			}
		}
	}
	close(NODE_STATUS);
	
	my $total_errors = @errors;
	if ($total_errors != 0)
	{
		return \@errors;
	}
	else
	{
		if ($wwn_found == 1)
		{
			return 0;
		}
		else
		{
			@errors = ('Transport Path is missing for this host');
			return \@errors;
		}
	}
}

# Check quorum
sub check_quorum
{
	my $scstat_binary=shift;
	my $hostname=shift;
	
	open (NODE_STATUS, "$scstat_binary -q |");
	while (<NODE_STATUS>)
	{
		chomp $_;
		if (/(Node votes:\s*$hostname\s*(\d+)\s*(\d+)\s*(\w+))/)
		{
			my $quorum_present=$2;
			my $quorum_possible=$3;
			my $quorum_status=$4;
			
			if (($quorum_present != 0) and ($quorum_present == $quorum_possible) and ($quorum_status =~ /Online/i))
			{
				return 0;
			}
			else
			{
				return $1;
			}
		}
	}
	close(NODE_STATUS);
	return 'Unknow quorum result. Quorum may be missing';
}

# Check IPMP
sub check_ipmp
{
	my $scstat_binary=shift;
	my $hostname=shift;
	
	open (NODE_STATUS, "$scstat_binary -i |");
	while (<NODE_STATUS>)
	{
		chomp $_;
		if (/IPMP Group:\s*$hostname\s*\S+\s*(\w*)/)
		{
			if ($1 !~ /Online/i)
			{
				return $_;
			}
			else
			{
				return 0;
			}
		}
	}
	close(NODE_STATUS);
	return 'No IPMP informations were found';
}

# Send to nagios
sub send_to_nagios
{
	my $errors_ref = shift;
	my @errors = @$errors_ref;
	my $total_errors = @errors;
	
	if ($total_errors == 0)
	{
		print "SUN Cluster status OK\n";
        exit(0);
	}
	else
	{
		print 'SUN Cluster problems';
		foreach (@errors)
		{
			print " - $_";
		}
		print "\n";
        exit(2);
	}
}

&check_opts;
