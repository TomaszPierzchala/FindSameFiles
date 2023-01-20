#! /usr/bin/perl -w
#
# SameFiles.pl  v1.07    20 I 2023  by Tomasz Pierzchala
#
# in 1.07 -  20I 2023: The found path are sorted - easier to find a pattern.
#					   To do this $upper path is added to the %SameFiles{$upper}
#					   array, which is finally sorted.
#
# in 1.06 -  3II 2011: Warning if exists are written at the and of the 
#                      report file
#
# in 1.05 - 30 I 2011: 1) in subroutine "are_same" warnings of problems with 
#                      file opening added as well as close of all opened files. 
#                      2) new "return" exits in sub "are_same" depending of
#                      situation type i.e. return -2, -1 if can't compare, 
#                      0 if files are different and 1 if files are same;
#
# in 1.04 - 18 I 2011: bug fixed - proper treatment of separated subgroups
#                      of same files for a given file size. 
#                      hash %samefiles changed to new structure %SameFiles
#                      e.g. For a given files A,B,...,H with a some file size : 
#                      two subgroups of same files could be found (A, C, E) 
#                      as well as subgroup (B, F, G).
#
# in 1.03 -  6 I 2011: skips symbolic links (modified sub wanted)    
#
use strict;
use Cwd 'abs_path';
use File::Find;
use POSIX qw(strftime);

# DECLARATION
my %files;    # {filesize => regular file in a given directory,...}
my %SameFiles;#{filename1 => @(file names same to filename1)}
#
my %progress; # { 5 => 0, 10 => 1, (percents) => active or not (1 or 0),...}
my $time0 = time; # script start time
my $all_combinations;# total number of checked combination (can be weighted with file size if 2nd option "-size" is used in &how_many_combinations(...)
my $ifsize; # 1 if "-size" is used , otherwise 0


# START  
my $WarningFile = "warnings.tmp";
close STDERR;
open STDERR,'>',$WarningFile or warn "Can't open temporary WARNING file \"$WarningFile\"\n";

if($#ARGV == -1){
    die "No path to compare ...\n";
}elsif($#ARGV == 0){
    find(\&wanted,$ARGV[0]);
}else{
    die "no more then 1 parameter (path) allowed\n";
}

my $results; #file name with a final report
while(1){
    $results="searching_report_". (strftime "%d%b%Y_%Hh%Mm%S", localtime);
    if(-f $results){
	sleep(1);
	next;
    }else{
	last;
    }
}
#
$| = 1; # no buffering of STDOUT (needed for progress watching)
#
%progress = &initialize_progress();
my $bitscombination = &how_many_combinations(\%files,"-size");

foreach(sort { $b <=> $a } keys %files){
    if($#{$files{$_}} > 0 ){ # if more than 1 file has a given size
#
	my $size=$_;
	my @same_files = @{$files{$_}};
	my %already_compared;
	foreach(@{$files{$_}}){
	    $already_compared{$_} = 0;
	}
#
	my $combinations;
	my $num_of_files = scalar keys %already_compared;
#	print "Num of files = $num_of_files\n";
	$combinations = $num_of_files * ($num_of_files - 1)/2;
	while(scalar keys %already_compared > 1 ){
	    foreach my $upper (keys %already_compared){
#
			delete $already_compared{$upper};
			my @paths;
			foreach my $lower (keys %already_compared){
			    my $ifsame = &are_same($upper,$lower);
			    if($ifsame == 1){
					delete $already_compared{$lower};
					push(@paths, $lower);
			    }elsif($ifsame == -1){
					last;
			    }elsif($ifsame == -2){
					delete $already_compared{$lower};
			    }
			}#end foreach $lower
			if($#paths > -1 ){
				# add upper file to list of found same files if any found
				$SameFiles{$upper} = [ @paths[0..$#paths], $upper];
			}	
	    }#end foreach $upper
	}#end while loop
#
	if($ifsize){
	    $all_combinations+= $size * $combinations;
	}else{
	    $all_combinations+= $combinations;
	}
# Shows progress :
	my $now = int($all_combinations/$bitscombination*20)*5;
	if($progress{$now}){# and $now == 5){
	    print "\rDone $now\% of the task";
	    $progress{$now} = 0;
	}
# end Show progress
    }#end if
}#end foreach keys %files

unless($all_combinations == $bitscombination){
    warn "\nProblem with number of all_combinations: $all_combinations\t$bitscombination\n";
}

# the Final report
open REPORT,">", "$results" or die "Error with open file $results\nSys: $!\n";
select REPORT;
print "\nIn directory : ",abs_path($ARGV[0]),"\n";
foreach(sort {(-s $a) <=> (-s $b)} keys %SameFiles){
    print "\nFollowing files of a size ",(-s $_)," B are same :\n";
    foreach ( sort {lc($a) cmp lc($b) } @{$SameFiles{$_}} )
    {
		print "$_\n";
    }
}
my $time1 = time;
print "\nTotal time of working ",($time1-$time0),"s\n";
# add warnings
close STDERR;
if( -s $WarningFile > 0 ){
	open WRG,'<',$WarningFile;
	print REPORT "\nWARNINGS :\n";
	foreach(<WRG>){
		print REPORT $_;
	}
	close WRG;
}
close REPORT;
unlink($WarningFile);
#
select STDOUT;
#
print "\nTotal time of working ",($time1-$time0),"s\n";
#

# END


# SUBROUTINES
sub wanted{
   push( @{$files{-s $_}},"$File::Find::name") if(-f $_ and (not -l $_) and (-s $_) =~ /^\d+/); 
}

sub initialize_progress{
    my $value = 0; my $add = 5;
    my %temprog;
    while($value < 100){
	$value+=$add;
	$temprog{$value} = 1; 
    }
    return %temprog;
}

sub how_many_combinations{ # in total for a given hash
#input is a hash like %files_names{file_size}
#for each keys (here file size) calculates number of files pair
#and sums it up to present it at return.
#    
# this "-size" option takes into account files size too

    $ifsize=1 if(scalar(@_)>1);
    my $number;
    my %hash =  %{$_[0]};
    foreach  ( keys %hash){
	my $tabsize = $#{$hash{$_}} + 1;
	my $toAdd = $tabsize * ($tabsize-1)/2;
# this "-size" option takes into account files size too
	(scalar(@_)>1 and $_[1] eq "-size") and $toAdd *= $_;
	$number += $toAdd;
    }
    return $number;
}
sub are_same{
    open fileA, $_[0] or warn "\nCan't open file $_[0]\n" and return -1;
    open fileB, $_[1] or warn "\nCan't open file $_[1]\n" and return -2;
    #
    foreach(<fileA>){
	my $line = <fileB>;
	close fileA and close fileB and return 0 unless($_ eq $line);
    }
    close fileA; close fileB;
    return 1;
}
