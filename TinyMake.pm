package TinyMake;
our $VERSION = '0.04';

=head1 NAME

TinyMake - A minimalist build language, similar in purpose to make and ant.

=head1 SYNOPSIS

   use TinyMake ':all';

   # a file statement without a rule is like a symbolic target
   file all => ['codeGen', 'compile', 'dataLoad', 'test'];

   file codeGen => ["database.spec"], sub { 
     # generate code here
     sh "touch $target";
   } ;

   file compile => ["codeGen"], sub { 
     # compile code here
     sh "touch $target";
   } ;

   file dataLoad => ["codeGen"], sub { 
     # load data here
	  sh "touch $target"
   } ;

   file test => ["compile", "dataLoad"], sub { 
     # test code here
     sh "touch $target";
   } ;
   # a file statement without prerequisites will be executed
   # if the target doesn't exist.
   file clean => sub { 
     # perform cleanup here
     sh "rm compile codeGen dataLoad test" 
   } ;

   make @ARGV

=cut

use strict;
use File::Find ;

require Exporter;
our @ISA = ("Exporter");
our @EXPORT_OK = qw(file make filetree group $target @changed @sources sh);
our %EXPORT_TAGS = (all => \@EXPORT_OK,);
#-------------------------------------------------------------------------------
#
# Exported variables (for use in rules)
#
#-------------------------------------------------------------------------------
our @changed = ();
our @sources = ();
our $target = undef;

my %ts = ();
my %tr = ();
my $first = undef;
#-------------------------------------------------------------------------------
#
# Show Dependency tree: Prints out a nested list of target and dependencies
#
#-------------------------------------------------------------------------------
sub show (@_){
  my ($node,$lvl) = @_;
  $node = $first unless (defined $node);
  $lvl = 0 unless (defined $lvl);
  if (exists $tr{$node}){
	 print "   " x $lvl . "*$node\n";
  }else{
	 print "   " x $lvl . "$node\n";
  }
  $lvl+=1;
  foreach (@{$ts{$node}}){
	 show ($_,$lvl);
  }
  $lvl-=1;
}
#-------------------------------------------------------------------------------
#
# Execute shell command: prints the shell command, the executes it
#
#-------------------------------------------------------------------------------
sub sh (@){
  print "@_\n";
  return qx(@_);
}
#-------------------------------------------------------------------------------
#
# Add a new target : 
#
#-------------------------------------------------------------------------------
sub file {
  my ($t,@rest) = @_;
  $first = $t unless defined $first;
  if (ref $rest[0] eq 'CODE'){
	 $tr{$t} = $rest[0];
  }else{
	 $rest[0] = [$rest[0]] unless (ref $rest[0] eq 'ARRAY');
	 $ts{$t} = $rest[0];
	 if ($rest[1]){
		$tr{$t} = $rest[1];
	 }
  }
}
#-------------------------------------------------------------------------------
#
# Add a new group of targets
#
#-------------------------------------------------------------------------------
sub group {
  my ($t,$href,$coderef) = @_;
  file $_ => $href->{$_}, $coderef foreach (keys %$href);
  file $t => [keys %$href];
}
#-------------------------------------------------------------------------------
#
# traverse the dependency tree post-orderly and return the list of targets
#
#-------------------------------------------------------------------------------
sub depends {
  my ($t,$store,$visited) = @_;
  return if (grep { $_ eq $t} @$visited);
  push @$visited, $t;
  my @kids = ();
  @kids = @{$ts{$t}} if (exists $ts{$t});
  depends($_,$store,$visited) foreach (@kids);
  push @$store, $t;
  @$store;
}

#-------------------------------------------------------------------------------
#
# Return the lastmodified time for each source file
#
#-------------------------------------------------------------------------------
{
  my %cachedsourcetimes = ();
  sub sourcetimes {
	 #  map {$_ => -M $_} @_;
	 my %result = ();
	 foreach my $source (@_){
		my $value = undef;
		#
		# if the source is not itself a target then 
		# cache its modification time. THis assumes
		# that such sources will not be modified as a side effect
		# of any production rule during execution!!!!
		#
		if (exists $tr{$source}){
		  $value = -M $source;
		}else{
		  $cachedsourcetimes{$source} = -M $source unless exists $cachedsourcetimes{$source};
		  $value = $cachedsourcetimes{$source};
		}
		$result{$source} = $value;
	 }
	 %result;
  }
}
#-------------------------------------------------------------------------------
#
# build a list of targets
#
#-------------------------------------------------------------------------------
sub make {
  my @result = ();
  @_ = ($first) unless (@_);
  my $exec = 0;
  foreach (@_){
	 my @actionables = grep {exists $tr{$_} } depends $_,[],[];
	 foreach (@actionables){
		$target = $_;
		@changed = @sources = ();
		@changed = @sources = @{$ts{$target}} if (exists $ts{$target});
		$exec = 1;
		if (-e $target){
		  my $targettime = -M $target;
		  my %sourcetimes = sourcetimes @sources;
		  $exec = @changed = grep { $sourcetimes{$_} < $targettime } @sources;
		}
		if ($exec){
		  $tr{$target}->() ;
		  push @result, $target;
		}
	 }
	 print "$_ is up-to-date\n" unless ($exec);
  }
  @result;
}

#-------------------------------------------------------------------------------
#
# Get a recursive listing of files in a given directory
#
#-------------------------------------------------------------------------------
sub filetree {
  my @found = ();
  File::Find::find sub{	 push @found, $File::Find::name }, @_;
  return @found;
}

1;

__END__


=head1 DESCRIPTION

This Perl Module allows you to define file-based dependencies similar to how make works.
Rather than placing the build rules in a separate Makefile or build.xml, the build rules
are declared using standard Perl syntax. TinyMake is effectively an inline domain-specific language.
Using make you might write a makefile that looks like this...

 test: compile dataLoad
   # test
   touch test

 codeGen: database.spec
	# generate code
	touch codeGen

 compile: codeGen
	# compile code 
	touch compile

 dataLoad: codeGen
	# load data
	touch dataLoad

 database.spec: # source file

The equivalent perl code using TinyMake would look like this...

 use TinyMake ':all';

 # some perl code
 .
 . 
 .
 file test => ["compile","dataLoad"], sub { # test
   `touch test`;
 } ;

 file codeGen => "database.spec", sub {  # generate code
   `touch codeGen`;
 } ;
  
 # some more perl code
 .
 . 
 .
 file compile => "codeGen", sub { # compile code
   `touch compile`;
 } ;

 file dataload => "codeGen", sub { # load data
   `touch dataLoad`;
 } ;

 make @ARGV;

Using TinyMake you declare a file dependency using the C<file>  subroutine.
This subroutine accepts a target filename as its first parameter,
and an arrayref of prerequisites and a rule coderef as its 2nd and 3rd parameters. 
The coderef passed in as the 3rd parameter will only be executed if the target file is out of date. 
A target file is considered to be out of date if ...

=over 4

=item 1.

the target file doesn't exist or...

=item 2.

any of the prerequisite files have been modified more recently than the target.

=back

TinyMake (as its name implies) is lacking in features, there are no implicit rules.
TinyMake doesn't know about C or any other language. All rules must be declared explicitly.
TinyMake provides the following subroutines...

=over 4

=item B<file>

   file $target => \@prerequisites, $code_reference;

The C<file> subroutine is used to declare a target, its prerequisites and a rule to invoke if the
target file is out of date. The supplied coderef does not get executed 
immediately. It will only be executed if the target is out of date. Typical usage would be...

 file "index.html" => ["bookmarks.txt", "site.xml"], sub {
   `xslfm -xsl index.xsl -files bookmarks.txt site.xml > index.html`;
 } ;

In the above example, C<index.html> is the target and both C<bookmarks.txt> and C<site.xml> are
prerequisites. If any of these two files change then C<index.html> should be rebuilt. The rule
to rebuild C<index.html> is the anonymous subroutine supplied as the 3rd parameter.

Just like Perl's native C<sort> subroutine, TinyMake exports some global variables which have special meaning 
within the scope of the supplied rule subroutine. These special variables are...

=over

=item B<$target> 

This is the target filename. This is equivalent to make's automatic variable C<$@>.

=item B<@changed> 

This is the list of prerequisite files which are newer than the target. This may not necessarily be all of the 
prerequisites supplied - only those which have changed since the target file was last modified. This is 
equivalent to make's automatic variable C<$?>.


=item B<@sources> 

This is the list of all prerequisite files which are dependents of the current target. This is 
equivalent to make's automatic variable C<$^>.

=back

Prerequisites must be enclosed in C<[ ... ]> square brackets. If there is only one prerequisite then
no square brackets are required. E.g. The following two file statements are valid...

   file "../classes/Sample.class" => "Sample.java", sub {
     sh "javac @changed"
   };

...or...

   file "../classes/Sample.class" => ["Sample.java"], sub {
     sh "javac @changed"
   };

To create Ant-style tasks, simply don't bother updating or touching the target file. 
No file modification dates are checked so the task will be executed if it is in the dependency tree for the active target.
The C<@changed> variable will contain all of the task's prerequisites, not just those that are newer than
the target. 

=item B<make>
  
  make @targets

The C<make> subroutine kicks off the build process. make takes 1 or more filenames/targets as its parameters
and determines ...

=over

=item 1. 

The order in which the target and its prerequisites should be built.

=item 2.

Which (if any) prerequisites are out of date and must be built.

=back 

If no arguments are supplied to C<make> then (like make and Ant) it assumes the first target that was defined using C<file> 
is the target to check. For this reason you should create an "all" file/synonym at the start of your perl script.
make returns a list of changed targets.

=item B<filetree>

  filetree @dirs

This is a helper function which returns a list of all of the files in the specified directory and subdirectories.


=item B<sh>

  sh $command

This is a helper function which executes the supplied string using qx() after printing the string to STDOUT. sh returns the value returned from qx()

=item B<group>

 group  $symbolicTarget => \%target_source_map, sub { rule code }

Imagine a scenario in which you have a directory with a number of B<.txt> files in it. Each of the B<.txt>
files must be converted to corresponding B<.html> files. Using standard makefile syntax you would do 
something like this...

   .SUFFIXES: .txt .html
  
   .txt.html:
       ${HTML_COMPILER} $< > $@

Using TinyMake there are 2 ways to do this. The first is to create a hash of html-to-txt files. This could
be done as follows...

   my %html2txt = map {/(.*)txt$/; "$1html" => $_ } glob "*.txt";

The next step would be to call C<file> for each key/value combination as follows...

   foreach (keys %html2txt){
     file $_ => $txt2html{$_}, sub {
       # convert all .txt files to .html files
       `cp $changed[0] $target`;
     } ;
   } 

Once we've create a file target for each html file with a corresponding .txt file as the prerequisite, we 
would probably want to create a catchall target under which to group all of the html files...
 
 file html => [keys %html2txt];

We can now build all of the html files by calling C<make 'html';>. 
Since this kind of construct is pretty common there is a shorthand way to do this...

   group html => {map {/(.*)txt$/; "$1html" => $_} glob "*.txt"}, sub {
     # convert .txt file to .html
     `cp $changed[0] $target`;
   } ;

What this effectively does is create multiple file targets for each .html file and create a synonym called
"html". Remember - the rule block for a group applies to each key/value pair in the supplied hash reference, not the
group name which is really just a synonym. The rule block above will never be called with "html" as the
target. Instead it will be called for each key/value combination where key is the target and value is the
the prerequisite/s. 

=head1 SAMPLE CODE

The following code is a sample perl script that uses TinyMake to compile a tree of java source code
and construct a C<.JAR> archive file from the built tree.

   use strict;
   use TinyMake ':all';
   
   my $sourcepath  = "./java";
   my $classpath   = "../lib/classes";
   my $outputpath  = "../bin";
   my $project_jar = "$outputpath/project.jar";
   #
   # build full jar by default
   #
   file default => $project_jar;
   #
   # create a map of .class to .java files
   #
   my %CLASS_JAVA =  map {
     /$sourcepath(.*)java$/; 
     "$outputpath$1class" => $_ 
   } grep /\.java$/, filetree $sourcepath;
   #
   # group the class-to-java map under the
   # 'compile' synonym
   #
   group compile => \%CLASS_JAVA, sub { 
     sh "javac -d $outputpath -classpath $classpath @changed" 
   } ;
   
   #
   # rebuild the jar if any of the .class files change
   #
   file $project_jar => [keys %CLASS_JAVA], sub {
     sh "jar -cvf $target -C $outputpath com";
   } ;

   #
   # clean build
   #
   file clean => sub { 
     sh "rm -R $outputpath/com";
     sh "rm $project_jar"; 
   };
     
   make @ARGV;

=head1 AUTHOR

Walter Higgins   walterh@rocketmail.com

=head1 BUGS

'file' prerequisites must be filenames, you should not use a synonym as a prerequisite to a 'file'.
e.g. 

   # WRONG !!!
   file compile => ["project.html", "project.exe"];
   file "project.tgz" => "compile", sub { ... } ;

This is incorrect because TinyMake assumes that all prerequisites are files.
The correct way to do it is like this...

   # CORRECT 
   my $compile = ["project.html", "project.exe"];
   file compile => $compile;
   file "project.tgz" => $compile, sub { ... };

Please also refer to the java compilation example above.

=head1 SEE ALSO

http://www.xanadb.com/archive/perl/20050906

http://www.xanadb.com/archive/perl/20050818

http://www.xanadb.com/archive/perl/20050815

http://martinfowler.com/articles/rake.html

=cut 
