#
# Module: AppCore::Web::ReportViewer;
#
# ReportViewer is a generic untility class that lets you throw a blob of SQL at it and it makes a nice pretty report out of it, complete
# with a parameter UI thanks to AppCore::Web::Form.
#
# The actual specs of the report model is a only a wee bit more complex than that - but really it is that simple - throw SQL together,
# throw it into a hash with some other nice fields, and voila - the ReportViewer (and whatever template you use)
# does the dirty work of running the query, throwing it in the template, adding the "options" UI, creating the table header and body, etc.
# Sort of like how the "wizard" side of Microsoft Reporting Services works - quick and easy reporting, or that's the idea anyway.
#
# See the __DATA__ section for a complete working example report model (well, working if you have those tables and classes)
# and a generic report viewer template you can use for just about any basic report and works with this class.
#
package AppCore::Web::ReportViewer;
{
	use strict;
	
	use AppCore::Web::Common;
	use AppCore::Web::Form;
	
	####################################

	our $STASH;
	
	sub set_stash
	{
		shift;
		$STASH = shift;
	}
	
	sub stash { $STASH }
		
	sub _new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};
		
		$args->{file} ||= '';
		
		$args->{tmpl} = AppCore::Web::Common::load_template($args->{file}) if $args->{file};
		$args->{req}  = $req;
		
		die "Unable to load template '$args->{file}'" if !$args->{tmpl} && $args->{file};
		
		my $self = bless $args, $class;
		
		return $self;
	}
	
	sub set_template
	{
		my $self = shift;
		my $file = shift;
		
		$self->{file} = $file;
		# TODO: This is a hack - we just assume that if $file is a reference, it's HTML::Template-compatible,
		# but I'm too lazy to do UNIVERSAL::isa for the different compatible derivations right now...
		return $self->{tmpl} = ref $file ?  $file : AppCore::Web::Common::load_template($file);
	}
	
	sub set_file{ shift->set_template(@_) }
	
	
	sub x
	{
		my($x,$k,$v)=@_;
		if(defined $v)
		{
			$x->{$k}=$v;
	#         	print STDERR AppCore::Common::MY_LINE().": x('$k') := '$v'\n";
		}
	
		$x->{$k};
	}
	
	sub req { shift->{req} }
	
	sub tmpl { shift->{tmpl} }
	
	####################################
	
	sub new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};
		
		$args->{file} ||= ''; 
		$args->{output_format} ||= 'html';
		
		return $class->_new($req, $args);
	}
	
	sub set_report_model
	{
		my ($self, $report) = @_;
		$self->{report_model} = $report;
		
		my $field_counter = 0;
		foreach my $arg (
			grep { !$_->{hidden} } 
				@{ $report->{args} || [] })
		{
			# Perform an in-place audit of existing values
			$arg->{field} = 'field'.(++$field_counter)
				if !$arg->{field};
			
			$arg->{type} = 'database'
				if $arg->{linked} && 
				  !$arg->{type};
		}	
	}
	
	sub report_model { shift->{report_model} };
	
	sub set_output_format
	{
		my $self = shift;
		my $fmt = lc shift || 'html';
		if($fmt ne 'html' && 
		   $fmt ne 'xls'  &&
		   $fmt ne 'json')
		{
			warn $@ = ref($self)."->set_output_fmt('$fmt'): Invalid/unknown output format '$fmt', defaulting to HTML.";
			return undef;
		}
		return $self->{output_format} = $fmt;
	}
	
	sub output_format
	{
		return lc shift->{output_format};
	}
	
	sub set_paging
	{
		my $self = shift;
		my ($start,$length) = @_;
		$self->{page_start} = $start ? $start : 0;
		$self->{page_length} = $length ? $length : 50;
	}
	
	sub set_message
	{
		my $self = shift;
		my $msg = shift;
		$self->{msg} = $msg;
	}
	
	sub page_start  {shift->{page_start}}
	sub page_length {shift->{page_length}}
	
	sub generate_report
	{
		my ($self, $arg_hash) = @_;
		
		my $report = $self->report_model;
		
		my $output_data = {};
		
		# Get the args
		my $arg_data_complete = 1;
		my @arg_data;
		{
			my $arg_meta = $report->{args};
		
			foreach my $arg_ref (@{$arg_meta || []})
			{
				# Get arg value from UI
				$arg_ref->{value}
					= $arg_hash->{$arg_ref->{field}}
					if !$arg_ref->{hidden};
					
				if(!defined $arg_ref->{value})
				{
					$arg_data_complete = 0;
				}
				
				push @arg_data, $arg_ref;
			}
		}
		
		$output_data->{arg_data_complete} = $arg_data_complete;
		
		#die Dumper \@arg_data, $arg_hash, $arg_data_complete;
		
		# Get columns if given in $report
		my @report_columns;
		if(ref $report->{columns} eq 'ARRAY')
		{
			@report_columns = @{$report->{columns} || []};
		}	
		
		# Get the data
		my @report_data;
		if($arg_data_complete)
		{
			if($report->{sql})
			{
				my @sql_args = map { $_->{value} } @arg_data;
				
				my ($listref, $last_sth) =
					AppCore::DBI->bulk_execute(
						$report->{sql},
						@sql_args
					);
					
				@report_data = @{ $listref || [] };
				
				# Extract order and name of fields returned if not specified
				# in the report config
				if(!@report_columns &&
					$last_sth)
				{
					my @field_list;
					
					# Following is based on http://search.cpan.org/~capttofu/DBD-mysql-4.028/lib/DBD/mysql.pm#STATEMENT_HANDLES
					my $names = $last_sth->{'NAME'};
					my $numFields = $last_sth->{'NUM_OF_FIELDS'} - 1;
					for my $i (0 .. $numFields) {
						#printf("%s%s", $i ? "," : "", $$names[$i]);
						push @field_list, $$names[$i];
					}
					
					@report_columns = map {{
						field => $_,
						title => guess_title($_)
					}} @field_list;
				}
				
			}
			elsif(ref $report->{data} eq 'ARRAY')
			{
				@report_data = @{ $report->{data} || [] };
				
				if(!@report_columns)
				{
					my $columns_listref = undef;
					
					# Since this is raw arrayref data, we must grab the list
					# of columns from the first row of data if not specified
					# in report configuration.
					if(@report_data)
					{
						my $first_row = $report_data[0];
						if(ref $first_row eq 'HASH')
						{
							# Sort keys of first row alphabetically
							my @keys = keys %{$first_row || {}};
							@keys = sort { $a cmp $b } @keys;
							
							$columns_listref = @keys;
						}
					}
					
					# Now $columns_listref SHOULD hold some data -
					# If its just a simple ARRAY of scalars, then convert
					# it to an array of hashrefs of {field,title} keys at minimum.
					# However, if the first row of $columns_listref is a HASH,
					# we graciously assume the data is in the right format and
					# just pass it on.
					if(ref $columns_listref eq 'ARRAY')
					{
						@report_columns = map {{
							field => $_,
							title => guess_title($_)
						}} $columns_listref;
					}
				}
			}
			elsif(ref $report->{data} eq 'CODE')
			{
				# Execute the code in {data}
				my ($data_listref, 
					$columns_listref) =
					$report->{data}->(
						$report,
						\@arg_data,
						$self->stash
					);
				
				if(!@report_columns)
				{
					# If the {data} coderef did NOT return a $columns_listref,
					# then we just use the keys of the first row of data
					if(!$columns_listref &&
						ref $data_listref eq 'ARRAY')
					{
						my $first_row = $data_listref->[0];
						if(ref $first_row eq 'HASH')
						{
							# Sort keys of first row alphabetically
							my @keys = keys %{$first_row || {}};
							@keys = sort { $a cmp $b } @keys;
							
							$columns_listref = @keys;
						}
					}
					
					# Only if @report_columns is not filled by the report config ...
					# Now $columns_listref SHOULD hold some data -
					# If its just a simple ARRAY of scalars, then convert
					# it to an array of hashrefs of {field,title} keys at minimum.
					# However, if the first row of $columns_listref is a HASH,
					# we graciously assume the data is in the right format and
					# just pass it on.
					if(ref $columns_listref eq 'ARRAY')
					{
						my $first_row = $columns_listref->[0];
						if(ref $first_row ne 'HASH')
						{
							@report_columns = map {{
								field => $_,
								title => guess_title($_)
							}} $columns_listref;
						}
						else
						{
							@report_columns = @{ $columns_listref };
						}
					}
				}
			}
			else
			{
				die "No data and no SQL in report";
			}
			
			# Apply row mudge hook if present
			if(ref $report->{row_mudge_hook} eq 'CODE')
			{
				foreach my $row (@report_data)
				{
					$report->{row_mudge_hook}->($row);
				}
			}
			
		
			# Audit data in report columns
			foreach my $data (@report_columns)
			{
				next if ref $data ne 'HASH';
				$data->{title} = guess_title($data->{field})
					if !$data->{title};
			}
			
			# Convert the report data into an arrayref of hashrefs containing an arrayref of columns containing a hashref with a value arg
			# E.g. convert [{ fooobar=>framitz }] to [{report_columns=>[{field=>foobar,value=>framitz}, ...]}]
			# where the '...' in the previous example contains foobar=>framitz and any other original keys from the original data
			foreach my $row (@report_data)
			{
				my @columns = map {{
					field => $_->{field},
					title => $_->{title},
					value => $row->{$_->{field}},
				}} @report_columns;
				
				$row->{report_columns} = \@columns;
			}
			
			$output_data->{columns} = \@report_columns;
			$output_data->{data}    = \@report_data;
			$output_data->{data_count} = scalar(@report_data);
		}
		
		return $output_data;
	}
	
	sub output
	{
		my $self = shift;
		
		my $req = $self->req;
		
		my $report = $self->report_model;
		
		# Create a hash for use in getting args from the UI
		my %arg_hash = map {
			
			# The resultant hash is just field=>value
			$_->{field} => $_->{value};
			
		} grep { !$_->{hidden} } 
			@{ $report->{args} || [] };
			
		# Load any values incomming from user into the arg hash
		if($req->{'AppCore::Web::Form::ModelMeta.uuid'})
		{
			AppCore::Web::Form->store_values($req, {
				args	=> \%arg_hash,
			});
		}
		
		# Do the report
		my $output_data = $self->generate_report(\%arg_hash);
		
		# Output the data
		if($self->output_format eq 'html')
		{
			my $tmpl = $self->tmpl;
			
			$tmpl->param('report_'.$_ => $report->{$_}) 
				foreach keys %$report;
				
			if($output_data->{arg_data_complete})
			{
				#die Dumper \@report_columns, \@report_data, \@arg_data;
				
				$tmpl->param('report_'.$_ => $output_data->{$_})
					foreach keys %$output_data;
			}
			else
			{
				print STDERR "Not executing report yet because arg data is incomplete\n";
				#die "Not enough data";
			}
			
			#die Dumper $output_data;
			
			$tmpl->param(view_message => $self->{msg});
			
			my $out = AppCore::Web::Form->post_process($tmpl, {
				args	     	=> \%arg_hash,
				validate_url	=> $self->{validate_url} || '/validate',
			});
			
			return $out;		
		}
		elsif($self->output_format eq 'xls')
		{
			# TODO
			die "Excel output not implemented yet.";
		}
		elsif($self->output_format eq 'json')
		{
			return $output_data;
		}
		else
		{
			die "Unknown output format";
		}
	}

	sub content_type
	{
		my $self = shift;
		my $fmt = $self->output_format;
		return $fmt eq 'xls'  ? 'application/vnd.ms-excel' : 
		       $fmt eq 'json' ? 'application/json' :
		                        'text/html';
	}
	
		
};

1;

__DATA__

# Sample report model:

{
	title => 'Exam Counts by Patient',

	# Instead of giving an sql arg, could we give a 'data' arg wich is either an ARRAY ref or a CODE ref?
	# CODE refs could return an ARRAY ref and still be passed a list of args ...?
	sql => q{
		set @setupid = ?;
		
		select p.patientid,
			first,
			last,
			count(examid) as count
		from patients p
			left join exams x on x.patientid=p.patientid
		where
			p.officeid = ? and
			(case when @setupid is null then 1 else
				(case when x.examsetupid = @setupid then 1 else 0 end)
			end) = 1
			
			
		group by patientid, first, last
		order by first, last
			
	},
	
	# If columns NOT specified, the report code will inspect the result set to
	# find the order the columns were returned in.
	# If using the 'data' coderef instead of SQL, the report code expects an array
	# of ($data_listref, $columns_listref) to be returned. If just a $data_listref
	# is returned, it will display the columns sorted in alphabetical order.
	# columns => [
	#	{
	#		field	=> 'patientid',
	#		title	=> 'Patient',
	#	},
	# ],
	
	args =>
	[
		{
			field => 'examsetupid', # field is used in the UI - autogenerated if no field name givne
			title => 'Exam Type', # Title can be guessed from the title of the linked class or the field if not given explicitly
			linked => 'NCS::ExamSetup', # if 'linked' given, a 'type' arg is expected to specify what type of UI input is needed (such as date, etc)
			#type => 'int',
			#fk_constraint => '', # SQL can be given in the form of a where clause (no WHERE need) to limit the vaulues returned from the linked class
			value => 1, # could be a coderef to get the default value, or a hashref with an 'sql' arg to execute...
		},
		
		{
			value => $class->stash->{office},
			hidden => 1,
		},
	],
	
	row_mudge_hook => sub {
		my ($row) = @_;
		
		my $patient = NCS::Patient->retrieve($row->{patientid});
		my $url = $patient->url;
		
		foreach my $key (qw/patientid first last/)
		{
			$row->{$key} = '<a href="'.$url.'">' . $row->{$key} . '</a>';
		}
		
		# ...
	},
};


##############

<!-- Sample report viewer template -->

<title>%%report_title%%</title>

<div class='body_content_panel'>

	<form action='%%post_url%%' method='POST' id='report-form'>
	
		<div class="panel visit-panel panel-default">
		
			<div class='panel-heading clearfix'>
				<h2 class='panel-title pull-left' style='padding-top:7.5px'>
					%%report_title%%
				</h2>
				<div class="btn-group pull-right">
					
					<!-- TODO: Add an 'export' option here -->
					
					<tmpl_if report_data_count>
						<p>Displaying <b>%%report_data_count%%</b> rows of data.</p>
					</tmpl_if>
				</div>
			</div>
			
			<!-- Form options - arguments requested -->
			<div class='panel-body form-table'>
				
				<!-- Transient message - not used yet, just keeping here if we want it -->
				<tmpl_if view_message>
					<div class='alert alert-info panel-message'><tmpl_var view_message></div>
					<script>
					$(function() {
						setTimeout(function() {
							$('.panel-message').hide('fast');// 1000 );
						}, 30 * 1000);
					});
					</script>
				</tmpl_if>

				

				<f:form uuid='report-viewer-%%user_userid%%' id='report' class='report-args'>
					<tmpl_loop report_args>
						<tmpl_unless hidden>
							<input bind='#args.%%field%%' label='%%title%%' type-hint='%%type_hint%%' type='%%type%%' class='%%linked%%' choices='%%choices%%' size='%%size%%' placeholder='%%placeholder%%' min='%%min%%' max='%%max%%'/>
						</tmpl_unless>
					</tmpl_loop>
					
					<button class='btn btn-primary get-report-btn'>Get Report</button>
				</f:form>
				
				<script>
				$(function() {
					$('.report-args input').on('change', function() {
						//$('.schedule-status-text').html($(this).val());
						
						var $spin = $('<i class="fa fa-spin fa-spinner" style="display:inline-block;margin:0 1rem;margin-top:8px"></i>');
						$spin.insertAfter($('.get-report-btn'));
						
						$('#report-form').submit();
					});
					
					$('.report-args input').first().focus();
				});
				</script>
				
			</div> <!-- /.panel-body -->
			
			<!-- Actual report data -->
			<div class='table-responsive'>
				
				<!-- This div is used by CSS to cast a faux shadow over the lines on the left & right when in 'responsive' mode (sub 768px width) or whatever CSS is set to -->
				<div class='table-responsive-shadow'></div>
				
				<table class="report-data table table-hover table-bordered " style='width:100%'><!--table-condensed table-striped -->
					<thead>
						<tmpl_loop report_columns>
							<th>%%title%%</th>
						</tmpl_loop>
					</thead>
					<tbody>
						<tmpl_loop report_data>
						
							<tr class='report-data-row'>
								<tmpl_loop report_columns>
									<td class='report-data-cell col-%%field%%'>
										<span class='value'>%%value%%</span>
									</td>
								</tmpl_loop>
							</tr>
						
						</tmpl_loop>
					</tbody>
				</table>
			</div><!--/.table-responsive-->
			
			<tmpl_if report_data_count>
				<div class='panel-footer form-table'>
			
					<p>Displaying <b>%%report_data_count%%</b> rows of data.</p>
					
					<!--<div class='form-button-wrapper'>
					
						TODO: Add export options here
				
					</div>-->
				</div>
			</tmpl_if>
		</div><!--/.panel-->
		
	</form>
</div>



