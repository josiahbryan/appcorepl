use strict;

=begin comment
	Package: AppCore::Web::Form
	
	Turns ...
	
		<f:form action="/save" method=POST" id="edit-form">
			<fieldset>
				<input bind="#driver.name">
				<input type="submit" value="Save Name">
			</fieldset>
		</f:form>
	
	Into ...
		
		<form action=".." method="..">
			<table>
				<tr>
					<td>
						<label for="..">Name:</label>
					</td>
					<td>
						<input id="edit-form-driver-name" name="#driver.name" value="Bob Jones">
					</td>
				</tr>
				<tr>
					<td></td>
					<td>
						<input type=submit value="Save Name">
					</td>
				</tr>
			</table>
		</form>
		
	Via:
	
		my $tmpl = HTML::Template->new("file_containing_f:form_code.tmpl");
		
		my $html = AppCore::Web::Form->post_process($tmpl->output, { driver => Driver::List->retrieve(234) });
		
		print $html;
=cut


package AppCore::Web::Form;
{
	use AppCore::Common;
	use AppCore::Web::Common;
	use AppCore::XML::SimpleDOM;
	use JSON qw/encode_json decode_json/;
	use Digest::MD5 qw/md5_hex md5_base64/;
	
	sub error
	{
		my ($title, $error) = @_;
		
		if(!$error && $title)
		{
			$error = $title;
			$title = "Error";
		}
		
		if(ref $error)
		{
			$error = "<pre>".Dumper($error,@_)."</pre>";
		}
		
		#exit;
		
		print "Content-Type: text/html\r\n\r\n<html><head><title>$title</title></head><body><h1>$title</h1>$error<hr></body></html>\n";
		exit -1;
	}

	
	sub store_values
	{
		my $self = shift;
		my $req = shift;
		my $form_opts = shift;
		
		my $uuid = $req->{'AppCore::Web::Form::ModelMeta.uuid'};
		error("Unable to Find Form UUID","Cannot find 'AppCore::Web::Form::ModelMeta.uuid' in posted data")
			if !$uuid;
		
		my $field_meta = AppCore::Web::Form::ModelMeta->by_field(uuid => $uuid);
		
		error("Invalid Form UUID","The 'AppCore::Web::Form::ModelMeta.uuid' in posted data does not exist in the database")
			if !$field_meta;
		
		my $hash = decode_json($field_meta->json);
		$hash ||= {};
		
		my $result_hash = {};
		
		my $class_obj_refs = {};
		
		foreach my $ref (keys %{ $hash })
		{
			my $class_obj = undef;
			my $class_key = undef;
			my $class_obj_name = undef;
			
			my $req_val = $req->{$ref};
			error("Value Not Defined for $ref",
				"Value not defined for '$ref' in data posted to server")
				if !defined $req_val;
			
			if($ref =~ /^#(.*?)\.(.*?)$/)
			{
				$class_obj_name = $1;
				$class_key = $2;
				
				$class_obj = $form_opts->{$class_obj_name};
				eror("Invalid bind '$ref'","Cannot find '$class_obj_name' in options given to store_values()") if !$class_obj;
				
				eval
				{
					$class_obj->set($class_key, $req_val);
					
					# Used to update() below on $class_obj
					$class_obj_refs->{$class_obj_name} = $class_obj;
					
					print STDERR "$ref: Storing '$req_val'\n";
				};
				if($@)
				{
					error("Error getting value for '$ref'",
						"Unable to read '$class_key' on '$class_obj_name': <pre>$@</pre>");
				}
			}
# 			else
# 			{
# 				#$val = $form_opts->{$ref};
# 				$result_hash->{$ref} = $req_val;
# 				error("Invalid bind '$ref'",
# 					"Value for '$ref' not defined in options given to store_values()") if !defined $val;
# 			}

			$result_hash->{$ref} = $req_val;
			
		}
		
		$_->update foreach values %$class_obj_refs;
		
		#error($result_hash);
		
		return $result_hash;
	}
	
	sub generate_stub_form
	{
		my $class = shift;
		my $cdbi_object = shift;
		
		my $meta = $cdbi_object->meta;
		#print Dumper $meta;
		
		my @edit_list = @{ $meta->{edit_list} || [] };
		if(!@edit_list)
		{
			@edit_list = map { $_->{field} } @{ $meta->{schema} || [] };
		}
		
		my $cdbi_class = ref $cdbi_object ? ref $cdbi_object : $cdbi_object;
		
		my $class_key = lc( $meta->{class_noun} || $cdbi_class );
		$class_key =~ s/:://g;
		
		my @xml;
		
		push @xml, "<f:form action='\%\%page_path\%\%/post' method='POST' id='edit-form' uuid='$cdbi_class'>\n";
		push @xml, "\t<table class='form-table'>\n";
		foreach my $field (@edit_list)
		{
			my $meta = $cdbi_object->field_meta($field);
			push @xml, "\t\t<row bind='#${class_key}.$field'/>\n"
				unless $meta->{auto};
		}
		push @xml, "\t\t<row>\n";
		push @xml, "\t\t\t<input type='submit' value='Save Changes'/>\n";
		push @xml, "\t\t\t<a style='color:rgba(0,0,0,0.5)'   href='javascript:void(window.history.go(-1))'>Cancel</a>\n";
		push @xml, "\t\t\t<a style='color:rgba(255,0,0,0.6)' href='\%\%page_path\%\%/delete' onclick='return confirm(\"Are you sure?\")'>Delete $meta->{class_noun}</a>\n";
		push @xml, "\t\t</row>\n";
		push @xml, "\t</table>\n";
		push @xml, "</f:form>\n";
		
		return join '', @xml;
	}
	
	sub post_process#($tmpl)
	{
		my $class = shift;
		my $tmpl = shift;
		#my $viz_style = lc( shift || 'html' );
		my $blob = ref $tmpl ? $tmpl->output : $tmpl;
		
		my $form_opts = shift || {};
		
		my ($data) = $blob =~ /(<f:form.*>.*<\/f:form>)/sgi;
		
		#error("No Data in Blob","No Data in Blob") if !$data;
		return $blob if !$data;
		
		#error("Error in Blob","Error in blob: $@<br><textarea>$data</textarea>");
		
		my $output;
		eval
		{
			my $form = AppCore::Web::Form->new($data);
			#die Dumper $form->visual('extjs')->render;
			$output = $form->render($form_opts);
			
		};
		if($@)
		{
			error("Error in Blob","Error in blob: $@<br><textarea>$data</textarea>");
		}
		#return $output unless $viz_style eq 'html';
		#error($output);
		#error("","<br><textarea rows=35 cols=150>$output</textarea>");
		$blob =~ s/(<f:form.*>.*<\/f:form>)/$output/sgi;
		
		return $blob;
	}
	
	
	# Function: new($data)
	# Create a new AppCore::Form object and load the data from $data. $data can be either a file name or a blob of XML 
	sub new#($data=undef)
	{
		my $class = shift;
		my $data = shift;
		#my $vars = shift;
		
		my $self = bless {}, $class;
		#$self->load($data,$vars);
		$self->load($data);
		
		return $self;
	}
	
		
	# Function: load($file_or_xml,$vars={})
	# Parses the xml using <AppCore::XML::SimpleDOM>, runs any perl <script> blocks inside the form, and sets up the internal model <AppCore::Form::Model>.
	sub load#($file_or_xml,$vars={})
	{
		my $self = shift;
		my $data = shift || die "Usage: \$form->load(\$file_or_xml,[\$vars])";
		my $vars = shift;
		
		my $dom = ref $data ? $data : AppCore::XML::SimpleDOM->parse_xml($data);
		
		$self->{dom} = $dom;
		
		if(!$dom->{uuid})
		{
			$dom->{uuid} = 'form'.md5_hex($data);
			$dom->{uuid} =~ s/[^a-zA-Z0-9]//g;
		}
		

		$self->_run_scripts($dom);
		
		#error("",$self);
		
		#$self->{model} = $self->{dom}->{model} = AppCore::Form::Model->new($self->dom->model,$self,$vars);
		#$self->_parse_model($dom,$vars);
	}

	# Function: _run_scripts
	# Internal function that evals all the scripts in the DOM for this form.
	sub _run_scripts#($node=undef,@stack=())
	{
		my $self = shift;
		my $node = shift;
		my @stack = @_;
		
		foreach my $node (@{$node->children})
		{
			my $path = join '/', map {$_->node} (@stack,$node);
			if(lc $node->node eq 'script' && lc $node->language eq 'perl')
			{
				eval $node->value;
				error($path,"<pre>$@</pre>") if $@;
			}
			
			$self->_run_scripts($node,@stack,$node);
		}
	}

	# Function: dom
	# Returns the DOM (an <AppCore::XML::SimpleDOM> object) for this form
	sub dom   { shift->{dom}   }

# 	# Function: model
# 	# Returns the model (an <AppCore::Form::Model> object) for this form
# 	sub model { shift->{model} }
	
	sub render
	{
		my $self = shift;
		my $form_opts = shift;
		
		$self->{form_opts} = $form_opts;
		
		my $dom = $self->dom;
		
		my $html = $self->_render_html($dom);
		
		#error($self->{field_meta});
		
		my $json = encode_json($self->{field_meta});
		
		my $field_meta = AppCore::Web::Form::ModelMeta->find_or_create({
			uuid	=> $dom->{uuid},
		});
		
		if($field_meta->json ne $json)
		{
			$field_meta->json($json);
		}
		
		$field_meta->timestamp(scalar(date()));
		$field_meta->update;
		
		return $html;
	}
	
	sub _is_pairtab
	{
		my $parent = shift;
		return lc $parent->node eq 'fieldlist' || lc $parent->node eq 'table';
	}
	
	
	sub _check_acl 
	{
		my $acl = shift;
		my $user = AppCore::Common->context->current_user;
		
		# Defaults to TRUE if NO ACL
		# Defaults to FALSE if HAS ACL but NO USER
		# Otherwise, it checks $acl against $self->user
		return $acl ? ( $user ? $user->check_acl($acl) : 0 ) : 1;
	}


	sub _strip_nbsp
	{
		local $_ = shift;
		$_ eq ' ' ? '' : $_;
	}

	sub _convert_spaces_to_nbsp
	{
		local $_ = shift;
		#s/\t/&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;/g;
		s/\s{2}/&nbsp;&nbsp;/g;
		$_;
	}

	sub _convert_newline 
	{
		my $x = shift;
		$x =~ s/(\n|\\n)/<br>/gi;
		return $x;
	}

	sub _remove_quotes
	{
		my $x = shift;
		$x =~ s/["']//g; #'"
		$x;
	}

	sub _format_render
	{
		my $format = shift;
		my $data = shift;
		
		$data = '&nbsp;' if $data eq '' || !defined $data || $data eq ' ';
		
		#print STDERR "data=[$data]\n";
		
		return $data;
	}

	sub _translate_module_uri($)
	{
		my $uri = shift;
		if($uri =~ /^module:(.*)/)
		{
			my $mod = $1;
			#my @parts = split/\//, $mod;
			#my $mod = shift @parts;
			
			my $http_bin = AppCore::Common->context->http_bin;

			$uri = join '/', $http_bin, $mod; #@parts;
		}
		
		
		return $uri;
	}

	sub _quote($)
	{
		my $x = shift;
		$x =~ s/(['"])/\\$1/g;
		return "\"$x\""; #"
	}

	sub _entity_encode($)
	{
		my $x = shift;
		return encode_entities($x);
		
	}

	sub _translate_js_fcall($$)
	{
		my $code = shift;
		my $row = shift;
		$code =~ s/[f\$]\(["']([^'"]+)['"]\)/_quote($row->{$1})/segi; #'
	#	error("",$code);
		return $code;

	}

	sub _get_field($$)
	{
		my $model = shift;
		my $ref = shift;
		
		#eval '*$model::error = undef'; undef $@;
		
		my $val = $model->$ref;
		if(defined $val)
		{
			return $val; #->value;
		}
		else
		{
			$@ = "No Such Model Variable: '$ref'";
			return undef;
		}
	}

	sub _perleval2($)
	{
		local $_ = shift;
		$_ = eval($_);
		$_ = "## $@ ##" if $@;
		$_;
	}

	sub _perleval($)
	{
		local $_ = shift;
		s/{{perl:(.*?)}}/_perleval2($1)/segi;
		return $_;
	}

	sub _render_html
	{
		my $self = shift;
		my $node = shift;
		my $t = shift || "\t";
		
		my @stack = @_;
		
		my @html;
		
		my $form = $self->dom;

		my $DEBUG = 0;
		
		#print STDERR $t, "--> ".$node->node."\n";
		
		if(!$node->{id})
		{
			my $x = $form->{_id_counter} ++;
			$node->{id} = "node$x";
		}
		
		my $path;
		eval
		{
			$path = join '/', map {$_->node} (@stack,$node);
		};
		
		#print STDERR "$path\n";
		
		if($@)
		{
			AppCore::Common::print_stack_trace();
			error("Error Loading Stack",[ map { ref $_ ? "$_" : ref $_ } ( @stack, $node ) ] );	
		}
		
		
		if(lc $node->node eq 'f:form')
		{
			
			#print STDERR "Form Frag: ".$node->is_form_fragment."\n";
			my $FORM_TAG_NAME = lc $node->is_form_fragment eq 'true' || $node->is_form_fragment eq '1' || !$node->{attrs}->{action} ? 'div' : 'form';
			$self->{is_form_fragment} = 1 if $FORM_TAG_NAME eq 'div';
			
			push @html, $t, "\t<$FORM_TAG_NAME style='border:0;padding:0;background:0;margin:0'";
			push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
			push @html, " name='$form->{id}' " if !$node->attrs->{name};
			push @html, " id='$form->{id}'" if !$node->{attrs}->{id};
			push @html, ">\n";
			
			push @html, $t, "\t\t<input type='hidden' name='AppCore::Web::Form::ModelMeta.uuid' value='$form->{uuid}'>\n" if $form->{uuid};
			
			foreach my $child ( @{$node->children} )
			{
				push @html, $self->_render_html($child,$t."\t\t",@stack,$node);
			}
			
			push @html, $t, "\t</". ($self->{is_form_fragment} ? 'div' : 'form').">\n";
			
			#$consumed = 1;
		}
		else
		{
			my $tt = $t;
			$tt =~ s/\t/    /g;
			my $name = lc $node->node;
			print STDERR $tt.$node->node."\n" if ($name ne '#text' || $node->value =~ /[^\s\n\r]/) && $DEBUG;
			
			#my $path = join('->',@stack,$node->node);
			
			my $consumed = 0;
			
			if($name eq '#comment')
			{
				push @html, $t, "<!--" . $node->value . "-->\n";
				$consumed = 1;
			}
			elsif($name eq '#text')
			{
				my $v = $node->value;
				if($v =~ /[^\s\n\r]/)
				{
					push @html, $t,$v,"\n";
				}
				$consumed = 1;
			}
# 			elsif($name =~ /^m:(.*)$/)
# 			{
# 				my $val = _get_field($model,$1);
# 				error("Error Reading Model at $path",$@) if $@;
# 				$val = $val->value || $val->default;
# 				push @html, $t, "<span id='$1'>$val</span>\n";
# 				
# 				$consumed = 1;
# 			}
			elsif($name =~ /^perl:(.*)$/)
			{
				my $val = eval($1);
				error("Error Parsing Perl at $path",$@) if $@;
				push @html, $t, "$val\n";
				
				$consumed = 1;
			}
			elsif($name eq 'hr')
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'>";
					
					if($node->title)
					{
						push @html, "<div ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, " class='f-hr-titled'>"._perleval($node->title)."</div>";
					}
					else
					{
						push @html, "<hr class='f-hr' ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, '/>';
					}
					push @html, "</td></tr>\n";
				}
				else
				{
					$consumed = 1;
					if($node->title)
					{
						push @html, "$t<div ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, " class='f-hr-titled'>"._perleval($node->title)."</div>\n";
					}
					else
					{
						push @html, "$t<hr class='f-hr' ";
						push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
						push @html, ">\n";			
					}
				}
			}
			elsif($name =~ /h[12345]/i)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					my $group = $node->group;
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'>\n";
					push @html, $t, "\t<".$name. (keys %{$node->attrs} ? " " : "");
					push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});
					push @html, '>';
					push @html, "<a name='$group'>" if $group;
					push @html, _perleval($node->value);
					push @html, "</a>" if $group;
					push @html, "</".$name.">\n";
					push @html, $t,"</td></tr>\n";
				}
				
			}
			elsif($name =~ /br/i)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				if($is_pairtab)
				{
					$consumed = 1;
					push @html, "$t<tr class='f-noborder'><td colspan='2'><br></td></tr>\n";
				}
				
			}
			elsif($name eq 'input' || $name eq 'row')
			{
				#if(!$node->type && ($node->ref || $node->bind))
				if($name eq 'row' && !$node->bind)
				{
					my $parent = $stack[$#stack];
					my $is_pairtab = _is_pairtab($parent);
					
					
					my $can_wrap = undef;
					if($is_pairtab)
					{
						my $key = 'allow-label-wrap';
						my $val = lc $parent->$key;
						$can_wrap = ($val eq 'false' || (defined $val && !$val)) ? 0:1;
					}
					
					push @html, $t;

					#push @html, $is_pairtab ? "<tr class='f-panelrow'><td colspan=2>" : "<div>";
					push @html, $is_pairtab ? "<tr>" : "<div>", "\n";
					
					#$node->{label} = $node->{attrs}->{label} = $model_item->label if !defined $node->label;
					$node->{label} = $node->{attrs}->{label} = AppCore::Common::guess_title($node->bind) if !$node->{label} && !$node->{ng}; # ng = no guess
					my $empty_label = 0;
# 					if($node->label)
# 					{
						my $text = $node->label;
						$text=~s/(^\s+|\s+$)//g;
						
						if($text)
						{
							#push @html, '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>' if $is_pairtab;
							push @html, $t, '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>'."\n" if $is_pairtab;
						
							push @html, $t."\t".'<label>', 
								    _convert_newline($node->label), 
								    ':</label> ';
							push @html, "\n".$t.'</td>'."\n" if $is_pairtab;
						}
						else
						{
							$empty_label = 1;
							
							push @html, $t, '<td>&nbsp;</td>', "\n" if $is_pairtab;
						}
						
# 					}
# 					else
# 					{
 						push @html, $t, "<td>\n" if $is_pairtab;
# 					}
					
# 					if($node->bind)
# 					{
# 						push @html, $self->_render_html($node,$t,@stack,$parent);
# 					}
# 					
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					#push @html, $t, "</td>\n";
					
					push @html, $t, $is_pairtab ? "</td>\n$t</tr>" : "</div>";
					push @html, "\n";
					
					$consumed = 1;
				}
				elsif($node->bind)
				{
					my $ref = $node->ref || $node->bind;
					
					$ref = $node->input if $name eq 'row' && !$ref;
					
					
# 					my $model_item = _get_field($model,$ref);
# 					error("Error Reading Ref '$ref' at $path",$@) if $@;
# 					error("Error Loading Ref '$ref' at $path","Ref '$ref' is null or not a reference [$model_item]: <pre>".Dumper($model).'</pre>') if !ref $model_item;

					my $class_obj = undef;
					my $class_key = undef;
					my $class_obj_name = undef;
					
					#my $value_ref = shift;
					my $val;
					
					$self->{form_opts} ||= {};
					if($ref =~ /^#(.*?)\.(.*?)$/)
					{
						$class_obj_name = $1;
						$class_key = $2;
						
						$class_obj = $self->{form_opts}->{$class_obj_name};
						
						if(!$class_obj)
						{
							if($self->{form_opts}->{allow_undef_bind})
							{
								$val = undef;
							}
							else
							{
								error("Invalid bind '$ref'","Cannot find '$class_obj_name' in options given to post_process() or render()");
							}
						}
						elsif(!ref $class_obj)
						{
							if($self->{form_opts}->{allow_undef_bind})
							{
								my $meta = $class_obj->field_meta($class_key);
								if($meta)
								{
									$val = $meta->{default} || undef;
								}
							}
							else
							{
								error("No object given for '$ref'","Found '$class_obj' in options given - but it's the string, not the a reference to a live object. You can set 'allow_undef_bind' to a true value in the options given to render() or you can pass a AppCore::DBI object");
							}
						}
						else
						{
							eval
							{
								#$value_ref = $class_obj->get($class_key);
								$val = $class_obj->get($class_key);
							};
							if($@)
							{
								error("Error getting value for '$ref'",
									"Unable to read '$class_key' on '$class_obj_name': <pre>$@</pre>");
							}
						}
					}
					else
					{
						$val = $self->{form_opts}->{$ref};
						error("Invalid bind '$ref'",
							"Value for '$ref' not defined in options given to post_process() or render()") if !defined $val;
					}
					
					$node->{value} = $val;
					
					
					#eval
					#{
					#$val = $model_item->value;
					#};
					#error("Error Loading Ref '$ref'","<pre>".$@->title.",".$@->text."</pre>");
					#$val = $model_item->default if !$val;
					
					# TODO: Load value from form opts
					
					$val = $node->default if !$val;
					
					# TODO: Add f:form 'readonly' flag
					my $readonly = $node->readonly eq 'true' || $self->{form_opts}->{readonly} ? 2 : 0; # TODO: Why 2?
					
					#error($model_item->node,$readonly) if $model_item->node ne 'tax';
					
					my $label_id = join '.', $form->{id}, _remove_quotes($ref);	
					$label_id =~ s/#//g;
					$label_id =~ s/\./-/g;
				
				
					my $parent = $stack[$#stack];
					my $is_pairtab = _is_pairtab($parent);
					my $can_wrap = undef;
					if($is_pairtab)
					{
						my $key = 'allow-label-wrap';
						my $val = lc $parent->$key;
						$can_wrap = ($val eq 'false' || (defined $val && !$val)) ? 0:1;
					}
					
					my $already_has_label = 0;
					if($parent->node eq 'row' && $parent->label)
					{
						$already_has_label = 1;
					}
					
					
					push @html, $t;

					
					my $type   = $node->type;
					
					if($class_obj)
					{
						my $meta = $class_obj->field_meta($class_key);
						error("No Meta for '$class_key'",
							"Unable to load metadata for column '$class_key' on object '$class_obj_name' (".ref($class_obj).")") if !$meta;
							
						if(!$type)
						{
							$type = $meta->{type};
							
							if($meta->{linked})
							{
								$type = 'database';
								$node->{class} = ''; # TODO HUH?
								$node->{source} = $meta->{linked}; # TODO review
							}
							elsif($type =~ /^enum/i)
							{
								my $str = $type;
								$str =~ s/^enum\(//g;
								$str =~ s/\)$//g;
								my @enum = split /,/, $str;
								s/(^'|'$)//g foreach @enum;
								
								$node->{choices} = join ',', @enum;
								
								$type = 'enum';
							}
							elsif($type =~ /^varchar/i)
							{
								$type = 'string';
							}
							elsif($type =~ /^int/i)
							{
								$type = 'int';
							}
						}
						
						if(!$node->label && !$already_has_label)
						{
							$node->{label} =  $meta->{label} || $meta->{title};
						}
					}
					
					#print STDERR "$path: $ref ($type) [$val]\n";
					
					
					$self->{field_meta}->{$ref} =
					{
						#class_obj_name => $class_obj_name,
						#class_key      => $class_key,
						type	       => $type,
					};
					
					my $format = $node->format;
					my $length = $node->length || $node->size;
					#$length = $node->length if !$length;
					$length = 30 if $type =~ /database/ && $node->class && !$length;
					$length = 9 if $type =~ /(int|float|num)/ && !$length;
					#error("",[$length,$node->length,$node->length]) if $node->node eq 'title';
					my $render = lc $node->render || 'ajax_input';
					$render = 'select' if $type eq 'enum' && $render ne 'radio';
					
					if($type eq 'enum' && $render eq 'select' && !$node->render)
					{
						my @choices = $node->options || split/,/, $node->choices;
						$render = 'radio' if @choices <= 2;
					}
					#die Dumper $node, $model_item, $render if $model_item->node eq 'customerid';
					#error("",[$length,$model_item->length,$node->length]) if $model_item->node eq 'title';
					

					my $hidden = $render eq 'hidden';
					
					my $rowid = 'tr.'.$label_id;
					$rowid =~ s/\./-/g;
					
					my $k_visb = "visual-border";
					my $v_visb = lc $node->$k_visb;
					my $vis_border = $v_visb eq 'true' || $v_visb eq '1';
					
					push @html, "<tr id='$rowid' ".($vis_border ? "class='f-border'":"").">\n" if $is_pairtab;
					
					my $empty_label = 0;
					
					if(!$already_has_label || $node->{label})
					{
						#$node->{label} = $node->{attrs}->{label} = $model_item->label if !defined $node->label;
						$node->{label} = $node->{attrs}->{label} = AppCore::Common::guess_title($node->bind) if !$node->{label} && !$node->{ng}; # ng = no guess
						if($node->label)
						{
							
							my $text = $node->label;
							$text=~s/(^\s+|\s+$)//g;
							
							if($text)
							{
#								my $first_row_child = lc $parent->node eq 'row' && $node->id eq $parent->children->[0]->id;
								push @html, $t, "\t", '<td class="td-label" valign="top"'.(!$can_wrap?' nowrap':'').'>', "\n" if $is_pairtab;
								#push || $first_row_child;
							
								push @html, $t, "\t\t", "<label for='$label_id' ".($render eq 'radio' ? "style='cursor:default !important'" : '').">", 
									_convert_newline($node->label), 
									':</label> ', "\n"  if !$hidden;
								push @html, $t, "\t", '</td>', "\n" if $is_pairtab; # || $first_row_child;
								#push @html, "\n$t<td>\n$t" if $first_row_child;
							}
							else
							{
								$empty_label = 1;
							}
							
						}
					}
					
# 					error("Error",{
# 						already_has_label => $already_has_label,
# 						html => encode_entities(join('',@html))
# 					}) if $ref eq '#driver.comments';
					
					#error($model_item->node,{length=>$length,type=>$type,format=>$format}) if $model_item->node eq 'parentopcode';
					
					my $hint = $node->hint;
					my $hint_pos_key  = "hint-position";
					my $hint_pos_key2 = "hint-pos";
					
					my $hint_pos = $node->$hint_pos_key || $node->$hint_pos_key2;
					
					if($hint_pos =~ /^[-+]\d+/)
					{
						$hint_pos = $hint_pos < 0 ? 'above' :
							    $hint_pos > 0 ? 'below' : 
							    '';
					}
					
					my $suffix = $node->suffix;
					my $prefix = $node->prefix;

					push @html, $t, "\t", '<td class="td-input"'.($empty_label ? ' colspan="2"':'').'>' if $is_pairtab; # && !$hidden;
					
					if($hint && ($hint_pos eq 'above' || $hint_pos eq 'top'))
					{
						push @html, "<span class='hint'>$hint</span><br>" if !$hidden;
					}
					
					
					if($readonly)
					{
						push @html, "$prefix<b><span class='f-input-readonly text ".($node->class?$node->class.' ':'')."' id='$label_id' "
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							.">".$val."</span></b>".($suffix ? "<label for='$label_id'>$suffix</label>" : ""). 
							($readonly == 2 ? "<input type='hidden' name='$ref' value='".encode_entities($val)."' id='out.$label_id'/>" : "");
					}
					elsif($type eq 'text')
					{
						my $rows = $node->rows || 10;
						my $cols = $node->cols || 40;
						push @html, "<textarea"
							." name='$ref'"
							." id='$label_id'"
							." rows=$rows"
							." cols=$cols"
							." class='text ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'>"
							.$val
							."</textarea>";
						
						# Disabling for now due to IExplore bug
						#push @html, "<script>\$('#$label_id').ext = new Ext.form.TextArea({applyTo:'$label_id',grow:true});</script>" if $self->{_extjs} && !$extjs_disable;
					}
					elsif($type eq 'database' || $type eq 'enum')
					{
						my $class  = $node->class;
						my $source = $node->source;
						
						if($render eq 'ajax_input')
						{
							#error("Ajax Input Not Implemented","Error in $path: Ajax Input not implemented yet.");
							if(!$node->class)
							{
								error("No AppCore::DBI Class Given","No AppCore::DBI Class given at path '$path' for ajax_input database model item");
							}
							
							my $class  = $node->class;
							my $source = $node->source;
							
							my $val_stringified = $val;
							my $clause = '';
							if($source)
							{
								error("Invalid source name","Invalid source '$source'") if $source !~ /^((?:\w[\w\d]+::)*\w[\w\d]+)\.([\w\d_]+)$/;
								my ($source_class,$source_column) = ($1,$2);
								
								error("$path","$source_class can't field_meta() [mark1: class=$class,source=$source, ref=$ref]")       if !$source_class->can('field_meta');
			
								my $meta = $source_class->field_meta($source_column);
								error("$path","$source_class didn't give any meta for $source_column (source='$source')") if !$meta;
								
								$clause = $meta->{link_clause} if $meta && $meta->{link_clause} && $meta->{link_clause} !~ /={{/;
								error("$path","Invalid characters in '$clause'")   if $clause && $clause =~ /(;|--)/;
							}
							
							#my $ret = $class->validate_string($val_stringified,$clause);
							#if(!$ret)
							#{
							#	$val_stringified = $class->stringify($val);
							#}
							
							$val_stringified = $val_stringified->stringify if UNIVERSAL::isa($val_stringified,$class);
							
							#die Dumper $val, $val_stringified, $ret if $label_id eq 'SearchForm.related_to';
							
							# Disabling for now because I don't like ForeignKeyField's handling of drop down with valid value, hit show all, red underline - neeed to polish, make more usable.
							if(0 && $self->{_defined_ext22})
							{
								push @html, "$prefix<div style='display:inline' f:db_class='$class' id='${label_id}_error_border'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')
									.($length ? "size=$length ":"")
									.($format ? "f:format="._quote($format)." ":"")
									.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
									."class='text f-ajax-fk ".($self->{_extjs} ? "x-form-text x-form-field" : "")." ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
									.($val_stringified?" value='".encode_entities($val_stringified)."'":'')
									." "
									#.($readonly ? 'readonly' : "")
									." id='$label_id' onfocus='select()'/></div>".($suffix ? "<label for='$label_id'>$suffix</label>" : "")."\n";
									
								my $noun = eval '$class->meta->{class_noun}' || "Linked Record";
								my $can_create = _check_acl($class->meta->{create_acl}) ? 'true' : 'false';
								my $can_read = _check_acl($class->meta->{edit_acl}) || _check_acl($class->meta->{read_acl}) ? 'true' : 'false';
								my $can_qc = $class->meta->{quick_create} && $class->check_acl($class->meta->{create_acl}) && ($class->can('can_create') ? $class->can_create : 1)  ? 'true':'false';
								
								push @html, "<script>Ext.onReady(function(){";
								push @html, "new Ext.app.ForeignKeyField({applyTo:'$label_id',";
								push @html, "className:'$class',";
								push @html, "sourceName:'$source',";
								push @html, "canQuickCreate:$can_qc,";
								push @html, "canCreate:$can_create,";
								push @html, "canEdit:$can_read,";
								push @html, "classNoun:'$noun',";
								push @html, "emptyText:'Enter a ".lc($noun)."'})})</script>\n";
							}
							else
							{
		
								
								push @html, "$prefix<div style='display:inline' f:db_class='$class' id='${label_id}_error_border'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')
									.($length ? "size=$length ":"")
									.($format ? "f:format="._quote($format)." ":"")
									.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
									."class='text f-ajax-fk ".($self->{_extjs} ? "x-form-text x-form-field" : "")." ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
									.($val_stringified?" value='".encode_entities($val_stringified)."'":'')
									." "
									#.($readonly ? 'readonly' : "")
									." id='$label_id' onkeydown='ajax_verify(this,\"$class\",\"$source\")' onfocus='select()'/></div><label for='$label_id'>$suffix</label>\n";
									
								my $noun = eval '$class->meta->{class_noun}' || "Linked Record";
								# Search btn
								#/linux-icons/Bluecurve/16x16/stock/panel-searchtool.png
								my $root = '/appcore'; # AppCore::Common->context->http_root;
								push @html, $t,qq{\t<img src="$root/images/silk/page_find.png" width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_do_search(event,"$label_id","$class","$source","$noun")' align='absmiddle' title="Search for a $noun">\n};
								
								if($class)
								{
									if(_check_acl($class->meta->{create_acl}))
									{
										# New btn
										push @html, $t,qq{\t<img src="$root/images/silk/page_add.png"  width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_fknew(event,"$label_id","$class","$source")' align='absmiddle' title="New $noun">\n};
									}
									
									# Edit btn
									#/linux-icons/Bluecurve/16x16/stock/stock-edit.png
									my $disp = $val && (ref $val ? eval '$val->id' : 1) ? 'default' : 'none';
									
									if(_check_acl($class->meta->{edit_acl}) || _check_acl($class->meta->{read_acl}))
									{
										#error("[$disp]","val=$val") if $node->node eq 'statusid';
										push @html, $t,qq{\t<img src="$root/images/silk/page_edit.png" width=16 height=16 style="cursor:hand;cursor:pointer;display:$disp" onclick='ajax_fkedit(event,"$label_id","$class","$source")' align='absmiddle' title="View/Edit $noun" id="ajax_edit_btn_$label_id">\n};
									}
								}
								
								# Progress/Error icon
								push @html, $t,"\t<img style='display:none;cursor:default' width=16 height=16 id='ajax_verify_output_$label_id' align='absmiddle' title='Checking data...'>";
								
								push @html, $t,"\t<script>setTimeout(function(){ajax_verify(\$('#$label_id'),\"$class\",\"$source\")},1000)</script>\n";
							}

							
							
						}
						elsif($render eq 'radio')
						{
							error("Cannot Render Database as Radio","Error in $path: Cannot render a database model item as a radio button") if $type eq 'database';
							
							my @list;
							my $auto_hint = 1;
							my $hint_column;
							
							my $val = $node->value  || $node->default;
							if($node->options)
							{
								my @opts = @{$node->options};
								foreach my $o (@opts)
								{
									my $x = $o->value;
									my $v = $o->data || $o->valueid;
									
									#$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
									$v = $x if $v eq '';
									push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								}
							}
							else
							{
								my @choices = split/,/, $node->choices;
								foreach my $c (@choices)
								{
									my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
									$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
									push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								}
							}
							
							#@list = map {{text=>$_,valueid=>$_,selected=>$_ eq $val}} @choices;
							$auto_hint = 0;
							#error("Choices",Dumper(\@list,$val));
							
							push @html, "\n";
							push @html, $t, "$prefix" if $prefix;
							push @html, $t, "\t<div class='radio-group'>\n";
							foreach my $op (@list)
							{
								my $radio_id = $label_id.'_'._entity_encode(_remove_quotes($op->{valueid}));
								
								#"onchange='\$(\"hint_$label_id\").innerHTML=this.options[this.selectedIndex].getAttribute(\"f:hint\");FormMgr.fieldChanged(this.getAttribute(\"f:bind\"),this.value)' onkeypress='var t=this;setTimeout(function(){t.onchange()},5)'";
								
								push @html, 
									"$t\t\t".
									"<div class='radio' onclick='\$(\"#$radio_id\").get(0).checked=true;\$(\"#$radio_id\").change()' style='cursor:pointer'><input style='cursor:pointer' type='radio' name='$ref' value="
									._quote(_entity_encode($op->{valueid}))
									.($hint_column ? " f:hint="._quote(_entity_encode($op->{hint})) : "")
									.($op->{selected} ? " checked":"")
									." id='$radio_id'"
									." onchange='\$(\"#$label_id\").val(this.value);if(this.getAttribute(\"f:hint\")) {\$(\"#hint_$label_id\").html(this.getAttribute(\"f:hint\"));}' "
									." onkeypress='var t=this;setTimeout(function(){t.onchange()},5)'"
									."><label for='$radio_id' style='cursor:pointer'> "
									._convert_spaces_to_nbsp(_entity_encode(_convert_newline($op->{text})))
									."</label>"
									.($op->{selected} ? "<script>setTimeout(function(){\$('#$radio_id').change()},5);</script>" : "")
									."</div>\n";
							}
							
							push @html, $t,"\t</div>\n";
							
							#onchange='FormMgr.fieldChanged(this.getAttribute(\"f:bind\"),this.value)' 
							#push @html, $t, "\t<input type='hidden' value='".encode_entities($val)."' id='$label_id'/>\n";
							
							push @html, $t, "\t<label for='$label_id'>$suffix</label>\n" if $suffix;
							push @html, $t, "\t<br>\n" if $auto_hint && $hint_pos eq 'below';
							push @html, $t, "\t<span class='hint' id='hint_$label_id'></span>\n";
							push @html, $t, "\t<script>setTimeout(function(){\$('#$label_id').change()},5);</script>\n";
							
							if($self->{_extjs})
							{
							#	push @html, "<script>\$('#$label_id').ext = new Ext.form.ComboBox({typeAhead: true,triggerAction: 'all',transform:'$label_id',forceSelection:true});</script>";
							}
							
							#error("",\@html);
						}
						elsif($render eq 'select')
						{
# 							my $live_filter = $node->filter;
# 							my ($lv_other_item,$lv_other_itemid, $lv_other_attr, $lv_my_attr, $lv_other_noun, $lv_my_noun);
# 							
# 							if($live_filter)
# 							{
# 								if($live_filter =~ /^(\w+)\.(\w+)=(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $2;
# 									$lv_my_attr    = $3;
# 								}
# 								elsif($live_filter =~ /^(\w+)\.(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $2;
# 									$lv_my_attr    = $2;
# 								}
# 								elsif($live_filter =~ /^(\w+)$/)
# 								{
# 									$lv_other_itemid = $1;
# 									$lv_other_attr = $1;
# 									$lv_my_attr    = $1;
# 								}
# 								else
# 								{
# 									error("Invalid 'filter' Attribute","Error in $path: 'filter' attribute '$live_filter' is not correctly formatted.");
# 								}
# 								
# 								$lv_other_item = _get_field($model,$lv_other_itemid);
# 								error("Error in 'filter' Attribute - Can't read Other Item '$lv_other_itemid' at $path",$@) if $@;
# 								error("Error in 'filter' Attribute - Can't read Other Item '$lv_other_itemid' at $path","Ref '$lv_other_itemid' is null or not a reference [$node]: <pre>".Dumper($model).'</pre>') if !ref $node;
# 								
# 								# Todo: right now, we're only going to use the primary key of $lv_other_itemid to simplify logic.
# 								# If we get more fancy and want to use another column other than the prikey of $lv_other_itemid (e.g. $lv_other_attr != the other prikey),
# 								# then we'll have to somehow tell the rendering function for $lv_other_item that it needs to include $lv_other_attr in the html output for
# 								# the javascript on the client to use for filtering. 
# 								# Therefore, we're going to ignore $lv_other_attr for now
# 								
# 								my $text = $node->label;
# 								$text=~s/(^\s+|\s+$)//g;
# 								$lv_my_noun = $node->label;
# 									
# 								$lv_other_noun = $lv_other_item->label;
# 								$lv_other_noun = AppCore::Common::guess_title($lv_other_itemid) if !$lv_other_noun; # ng = no guess;
# 							}
							
							
							
							my @list;
							my $auto_hint = 1;
							my $hint_column;
							if($type eq 'database')
							{
								my $key = $node->key; # || error("No Key","No key given to bind for $path");
								my $text = $node->text; # || error("No Text","No text given to bind for $path");
								$hint_column = $node->hint || undef;
								my $table = $node->table;
								my $clause = $node->clause || '1';
								my $orderby = $node->orderby;
								my $db = $node->db;
								
								my $class = $node->class;
								my $source = $node->source;
								# 103289pa, 1pc
								
								if($class && !$class->can('get_stringify_sql'))
								{
									error("$path","$class can't get_stringify_sql()");
								}
								
								if($class)
								{
									$text = $class->get_stringify_sql;
									$orderby = $class->get_orderby_sql if $class->can('get_orderby_sql');
									$key = $class->primary_column;
									$table = $class->table;
									$db = $class->meta->{db};
									
									#die Dumper $db,$class->db_Main->{Name} if $table eq 'program';
								}
								
								$orderby = $text if !$orderby;
								
								if($source)
								{
									error("Invalid source name","Invalid source '$source'") if $source !~ /^((?:\w[\w\d]+::)*\w[\w\d]+)\.([\w\d_]+)$/;
									my ($source_class,$source_column) = ($1,$2);
									
									error("$path","$source_class can't field_meta() [mark2: class=$class,source=$source, ref=$ref]")       if !$source_class->can('field_meta');
				
									my $meta = $source_class->field_meta($source_column);
									error("$path","$source_class didn't give any meta for $source_column") if !$meta;
									
									$clause = $meta->{link_clause} if $meta && $meta->{link_clause} && $meta->{link_clause} !~ /={{/;
									error("$path","Invalid characters in '$clause'")   if $clause && $clause =~ /(;|--)/;
								}
								
								error("No Key","No key given to bind for $path") if !$key;
								error("No Text","No text given to bind for $path") if !$text;
								
								#print STDERR "Debug: field ".$node->node.": text=$text, clause=$clause, orderby=$orderby (class=$class,source=$source)\n";
								
								my $hint_limit_key = 'max-hint-length';
								my $hint_len = $node->$hint_limit_key;
								my $hint_key = $hint_len && $hint_len =~ /^\d+$/ ? "concat(substr($hint_column,1,$hint_len),if(length(`$hint_column`)>$hint_len,'...',''))" : "`$hint_column`";
								
								#my $lv_my_attr_key = $lv_my_attr ? "`$lv_my_attr`" : "";
								#($lv_my_attr_key?",$lv_my_attr_key as `lv_attr`":'')."
								
								my $sql = "select `$table`.`$key` as `valueid`,$text as `text`".($hint_column?",$hint_key as `hint`":'')." from `$table` where ($clause) order by $orderby";
								#error("",$sql);
								my $q_get = AppCore::DBI->dbh($db)->prepare($sql);
								$q_get->execute();
								
								push @list, {valueid=>'-',text=>'(Unknown/NA)',hint=>''};
								push @list, $_ while $_ = $q_get->fetchrow_hashref;
								
								if($class->can('form_format_hint_text'))
								{
									$_->{hint} = $class->form_format_hint_text($_->{hint},$_) foreach @list;
								}
								
								my $value = $node->value || $node->default;
								
								my $got_sel = 0;
								foreach my $item (@list)
								{
									if($item->{valueid} eq $value)
									{
										$got_sel = 1;
										$item->{selected} = 1;
									}
								}
								
								if(!$got_sel && $value)
								{
									foreach my $item (@list)
									{
										if($item->{text} eq $value)
										{
											$got_sel = 1;
											$item->{selected} = 1;
										}
									}
								}
								
								#die "<pre>".Dumper(\@list,$node->value)."</pre>";
							}
							else
							{
								#my $val = $node->value  || $node->default;
								#my @choices = split/,/, $model_item->choices;
								##@list = map {{text=>$_,valueid=>$_,selected=>$_ eq $val}} @choices;
								#foreach my $c (@choices)
								#{
								#	my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
								#	$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
								#	push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
								#}
								
								my $val = $node->value  || $node->default;
								#error("",[$val, $node, $node]);
								if($node->options)
								{
									my @opts = @{$node->options};
									foreach my $o (@opts)
									{
										my $x = $o->value;
										my $v = $o->data || $o->valueid;

										#$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
										$v = $x if $v eq '';
										push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
									}
									
									# die "Xx";
								}
								else
								{
									my @choices = split/,/, $node->choices;
									foreach my $c (@choices)
									{
										my ($v,$x) = $c =~ /^([^=]+)?=?(.*)$/;
										$x = $v = $c if !defined $v || !defined $x || $x eq '' || $v eq '';
										push @list, {text=>$x,valueid=>$v,selected=>$v eq $val};
									}
								}


								$auto_hint = 0;
							}
							#error("",Dumper(@list));
							
							
							
							push @html, "$prefix"
								."<select"
								." name='$ref'"
								." f:model_item_class='$class'"
								." class='".($node->class?$node->class:'')."'"
								." id='$label_id'"
								." onkeypress='var t=this;setTimeout(function(){t.onchange()},5)'>\n".
								(join("\n",
									map { "$t\t".
										"<option value="
										._quote(_entity_encode($_->{valueid}))
										.($hint_column ? " f:hint="._quote(_entity_encode($_->{hint})) : "")
										#.($lv_my_attr ? " f:lv_attr="._quote(_entity_encode($_->{lv_attr})) : "")
										.($_->{selected} ? " selected":"")
										.">"
										._entity_encode($_->{text})
										."</option>" 
									} @list))
								."\n$t</select>\n";
								
							
							if($type eq 'database')
							{
								my $root   = '/appcore'; #AppCore::Common->context->eas_http_root;
								my $noun   = eval '$class->meta->{class_noun}' || "Linked Record";
								# Edit btn
								#/linux-icons/Bluecurve/16x16/stock/stock-edit.png
								#die "labelid=$label_id, val=$val <pre>".Dumper($val)."</pre>" if ref $val && $val !=10 ;
								my $disp = $val && (ref $val ? eval '$val->id' : 1) ? 'default' : 'none';
								#$@ = undef;
								if($class)
								{
									if(_check_acl($class->meta->{edit_acl}))
									{
										push @html, $t,qq{<img src="$root/images/silk/page_edit.png" width=16 height=16 style="cursor:hand;cursor:pointer;display:$disp" onclick='ajax_fkedit(event,"$label_id","$class","$source")' align='absmiddle' title="View/Edit $noun" id="ajax_edit_btn_$label_id">\n};
									}
		
									# New btn
									if(_check_acl($class->meta->{create_acl}))
									{
										# New btn
										push @html, $t,qq{<img src="$root/images/silk/page_add.png"  width=16 height=16 style="cursor:hand;cursor:pointer" onclick='ajax_fknew(event,"$label_id","$class","$source")' align='absmiddle' title="New $noun">\n};
									}
								}
								
								push @html, $t,qq|<script>setTimeout(function(){
										\$('#$label_id').oldAjaxFkSelectOnchange = \$('#$label_id').onchange;
										\$('#$label_id')._ajax_fk_select_onchange = _ajax_fk_select_onchange;
										\$('#$label_id').onchange = function(evt)
										{
											if(\$('#$label_id').oldAjaxFkSelectOnchange) {
												\$('#$label_id').oldAjaxFkSelectOnchange();
											}
											\$('#$label_id')._ajax_fk_select_onchange(evt);
										};
										\$('#$label_id').onchange()
									},5);</script>\n|;

							}
# 							elsif($self->{_extjs} && !$extjs_disable)
# 							{
# 								push @html, $t,"<script>\$('#$label_id').ext = new Ext.form.ComboBox({typeAhead: true,triggerAction: 'all',transform:'$label_id',forceSelection:true});</script>\n";
# 							}
							
							push @html, "$t<label for='$label_id'>$suffix</label>" if $suffix;
							push @html, ($auto_hint && $hint_pos eq 'below' ? "<br>" : "")
									."<span class='hint' id='hint_$label_id'>";
						}
					}
					elsif($render eq 'div' || $render eq 'span')
					{
						my $nn = $render eq 'div' ? 'div' : 'span';
						push @html, "$prefix<$nn "
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							."class='".($node->class ? $node->class.' ':'')."' "
							."id='$label_id'"
							.($val?">".encode_entities($val)."</$nn>":'>')
							.($suffix ? "<label for='$label_id'>$suffix</label>" : "");
					}
					else # All other rendering types (string, etc)
					{
						#push @html, "$prefix<div style='display:inline'><input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')."' f:bind='$label_id' "
						push @html, "$prefix<input name='$ref' type='".($render eq 'hidden' ? 'hidden' : 'text')."' "
							.($length ? "size=$length ":"")
							.($format ? "f:format="._quote($format)." ":"")
							.($type   ? "f:type="._quote($type)." ".($type =~ /(int|float|num)/ ? "style='text-align:right' ":""):"")
							."class='text ".($node->class?$node->class.' ':'').($readonly?'readonly ':'')."'"
							.($val?" value='".encode_entities($val)."'":'')
							." "
							#.($readonly ? 'readonly' : "")
							." id='$label_id'/>".($suffix ? "<label for='$label_id'>$suffix</label>" :"")."\n";

# 						unless($hidden)
# 						{
# 							my $x_type = "x-type";
# 							$x_type = $node->$x_type;
# 							$type = $x_type if $x_type;
# 							$type = $node->xtype if $node->xtype;
# 							#die Dumper $type,$node if $ref eq 'datelogged';
# 							
# 							if($type eq 'fraction')
# 							{
# 								push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.FractionField({applyTo:'$label_id'});</script>" if $extjs_enabled;
# 							}
# 							elsif($type eq 'date')
# 							{
# 								#push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.DateTime({applyTo:'$label_id',dateFormat:'Y-m-d',timeFormat:'H:i:s'});var field=\$('#$label_id');field.name='$ref';field.style.display='none';</script>";
# 								
# 								push @html, "<script>\$('#$label_id').ext = EAS.Data.XType.Date.applyTo('$label_id')</script>";
# 							}
# 							elsif($type eq 'datetime')
# 							{
# 								#push @html, "<script>\$('#$label_id').ext = new Ext.ux.form.DateTime({applyTo:'$label_id',dateFormat:'Y-m-d',timeFormat:'H:i:s'});var field=\$('#$label_id');field.name='$ref';field.style.display='none';</script>";
# 								
# 								push @html, "<script>\$('#$label_id').ext = EAS.Data.XType.DateTime.applyTo('$label_id')</script>";
# 							}
# 							elsif($type eq 'number')
# 							{
# 								push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id'});</script>" if $extjs_enabled;
# 							}
# 							elsif($type eq 'float')
# 							{
# 								push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id',allowDecimals:true});</script>" if $extjs_enabled;
# 							}
# 							elsif($type eq 'integer')
# 							{
# 								push @html, "<script>\$('#$label_id').ext = new Ext.form.NumberField({applyTo:'$label_id',allowDecimals:false});</script>" if $extjs_enabled;
# 							}
# 							elsif($type =~ /^custom:(.*)/)
# 							{
# 								my $xtype_class = $1;
# 								push @html, "<script>\$('#$label_id').ext = ${xtype_class}.applyTo('$label_id')</script>";
# 							}
# 							else
# 							{
# 								push @html, "<script>\$('#$label_id').ext = new Ext.form.TextField({applyTo:'$label_id'});</script>" if $extjs_enabled;
# 							}
# 
# 						};
						
						
					}
					
					if($hint && $hint_pos ne 'above')
					{
						push @html, ($hint_pos eq 'below' ? '<br>': '') . "<span class='hint'>$hint</span>"; # .($is_pairtab ? "" : "<br>");
					}
					
					
# 					push @html, "\n$t<script>FormMgr.regField('$label_id',\$('#$label_id'))</script>";
# 					my $calc = $node ? $node->calculate : undef;
# 					push @html, "\n$t<script>\$('#$label_id').calculate = function(mgr){FormMgr.setBindPrefix("._quote($model->id)."); return $calc};</script>\n" if $calc;
# 					
# 					if(!$hidden)
# 					{
# 						push @html, "\n$t<script>var e=\$('#$label_id');if(e) e.onkeyup=function(){FormMgr.fieldChanged(this.getAttribute('f:bind'),this.value)};".
# 						($val ? "setTimeout(function(){\$('#$label_id').onkeyup();/*debug('$label_id initalized')*/},100)" : "").
# 							#"setTimeout(function(){\$('#$label_id').onkeyup();debug('$label_id initalized')},10)".
# 						#	"if(\$('#$label_id').ext){\$('#$label_id').ext.addListener('change',\$('#$label_id').onkeyup);".
# 						#	                       "\$('#$label_id').ext.addListener('keyup',\$('#$label_id').onkeyup);}".
# 									"</script>\n" if !$readonly;
# 						#push @html, $is_pairtab ? "$t</td></tr>\n" : "$t<br/>\n";
# 					}
					
					push @html, "$t</td></tr>\n" if $is_pairtab;
					$consumed = 1;
				}
			}
			elsif($name eq 'panel')
			{
				my $lay = $node->layout;
				
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				push @html, $t, "<tr class='f-panelrow'><td colspan=2>" if $is_pairtab;
				
				my $old_t = $t;
				$t .= "\t";
				
				if($lay eq 'columns')
				{
					push @html, $t, "<table cellspacing=0 class='f-panel ".$node->class."' border=0 ".($node->width ? 'width='.$node->width : '')."><tr>\n";
					
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					push @html, $t, "</tr></table>\n";
				
				}
				else
				{
					my $parent = $stack[$#stack];
					
					my $l_col = 0;
					if(lc $parent->layout eq 'columns' && lc $parent->node eq 'panel')
					{
						$l_col = 1;
					}
					
					push @html, $t, "<td valign='top'>\n" if $l_col;
					
					if($node->title)
					{
						push @html, $t, "<fieldset class='f-panel ".$node->class."'><legend>".$node->title."</legend>\n";
					}
					else
					{
						push @html, $t, "<div class='f-panel ".$node->class."'>\n";
					}
					
						
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					
					if($node->title)
					{
						push @html, $t, "</fieldset>\n";
					}
					else
					{
						push @html, $t, "</div>\n";
					}
					
					push @html, $t, "</td>\n" if $l_col;
				}
				
				push @html, $old_t, "</td></tr>" if $is_pairtab;
				
				$consumed = 1;
			}
			elsif($name eq 'fieldlist')
			{
				my $id = $node->id;
				push @html, $t, "<table cellspacing=0 class='f-fieldlist ".$node->class."' border=0 ".($id?"id='$id'":'')." ".($node->width ? 'width='.$node->width : '').">\n";
				
				foreach my $child (@{$node->children})
				{
					push @html, $self->_render_html($child,$t."\t",@stack,$node);
				}
				
				push @html, $t, "</table>\n";

				$consumed = 1;
			}
			elsif($name eq 'column')
			{
				if(@stack <= 1)
				{
					#push @html, "## C1: Must use tag 'column' inside a panel with layout type 'columns' ##";
					error("Layout Error at $path","C1: Must use tag 'column' inside a panel with layout type 'columns'");
				}
				else
				{
					my $parent = $stack[$#stack];
					if(lc $parent->node ne 'panel')
					{
						#push @html, "## C2: Must use tag 'column' inside a panel (".$parent->node.") ##";
						error("Layout Error at $path","C2: Must use tag 'column' inside a panel (".$parent->node.")");
					}
					elsif(lc $parent->layout ne 'columns')
					{
						#push @html, "## C3: Parent 'panel' must have layout type 'columns' ##";
						error("Layout Error at $path","C3: Parent 'panel' must have layout type 'columns'");
					}
					else
					{
						$consumed = 1;
						
						push @html, $t, "<td valign='top' class='f-column' ".($node->style ? 'style="'.$node->style .'"' : '')." ".($node->width ? 'width='.$node->width : '').">\n";
						if($node->title)
						{
							push @html, $t, "<fieldset><legend>".$node->title."</legend>\n";
						}
						
						foreach my $child (@{$node->children})
						{
							push @html, $self->_render_html($child,$t."\t",@stack,$node);
						}
						
						if($node->title)
						{
							push @html, $t, "</fieldset>\n";
						}
						
						push @html, $t, "</td>\n";
					}
				}
			}
# 			elsif($name eq 'submit')
# 			{
# 				if($self->{is_form_fragment})
# 				{
# 					warn "Not including SUBMIT in a form fragment - do it yourself";
# 				}
# 				else
# 				{
# 					my $method = uc $node->method || 'GET';
# 					my $uri = $node->uri;
# 					my $label = $node->label;
# 					
# 					# Conditionally translates URIs like 'module:forms/echo?x=1' to appros URLs for this EAS instance
# 					$uri = _translate_module_uri($uri);
# 					
# 					if($model->data_override && $model->data_override->{post_url})
# 					{
# 						$uri = $model->data_override->{post_url};
# 					}
# 					
# 					my $parent = $stack[$#stack];
# 					my $is_pairtab = _is_pairtab($parent);
# 						
# 					if($self->{_buttonbar})
# 					{
# 						push @html, "<script>Ext.onReady(function(){\n";
# 						push @html, "var currentForm=\$('".$model->id."');currentForm.setAttribute('method','$method');currentForm.setAttribute('action','$uri');\n";
# 						push @html, "PCI.ButtonBar.addButton({icon:'Save',text:'$label',handler:function(){FormMgr.preprocess_form();\$('".$model->id."').submit();}});\n";
# 						push @html, "PCI.ButtonBar.addButton({icon:'Cancel',text:'Cancel',handler:function(){window.history.go(-1);},side:'right'});\n";
# 						push @html, "});</script>";
# 						
# 						
# 					}
# 					else
# 					{
# 						push @html, $t;
# 						push @html, "<tr><td>&nbsp;</td><td>" if $is_pairtab;
# 						
# 						if(!$model->is_readonly)
# 						{
# 							push @html, "<button ";
# 				#			class="form-ctrl"
# 							push @html, "class='form-ctrl ".($node->class?$node->class:'')."' ";
# 							push @html, "onclick='FormMgr.submit(this,\$(\"".$model->id."\"))' f:method='$method' f:uri='$uri'";
# 							push @html, ">";
# 							push @html, $label;
# 							
# 							my @children = @{$node->children};
# 							foreach my $child (@children)
# 							{
# 								push @html, $self->_render_html($child,$t."\t",@stack,$node);
# 							}
# 							
# 							push @html, "</button><script>".qq|
# 								setTimeout(function(){
# 									var f=\$('|.$model->id.qq|');
# 									f.setAttribute('method','$method');
# 									f.setAttribute('action','$uri');
# 									f.onsubmit=function(){FormMgr.preprocess_form()}
# 								},100);
# 							|."</script>";
# 						}
# 						
# 						my $can_reset = lc $node->can_reset;
# 						#error("",$can_reset);
# 						$can_reset = $can_reset eq 'true' || $can_reset eq '1' ? 1:0;
# 						
# 						push @html, "<a href='javascript:window.history.go(-1)' class='form-ctrl f-submit-reset-link noprint'>Return to the previous page without making any changes</a>" if $can_reset;
# 						
# 						push @html, "</td></tr>" if $is_pairtab;
# 						
# 						push @html, "\n";
# 					}
# 				}
# 				
# 				$consumed = 1;
# 			}
# 			
			if(!$consumed)
			{
				my $parent = $stack[$#stack];
				my $is_pairtab = _is_pairtab($parent);
				next if $is_pairtab && lc $node->node eq 'br';
				
				my $name = lc $node->node;
				
				## Wierd Bug here - need to investigate
	#			$name = 'h1' if $name eq 'label';
				
				push @html, $t, "<".$name. (keys %{$node->attrs} ? " " : "");
				push @html, join (" ", map { $_ . "=\""._perleval($node->attrs->{$_})."\"" } keys %{$node->attrs});


				if(@{ $node->children })
				{
					push @html, ">\n";
					foreach my $child (@{$node->children})
					{
						push @html, $self->_render_html($child,$t."\t",@stack,$node);
					}
					push @html, $t, "</".$name.">\n";
				}
				elsif(($node->value && !$node->{attrs}->{value}) || $name eq 'script')
				{
					push @html, '>';
					push @html, _perleval($node->value) unless $node->src;
					push @html, "</".$name.">\n";
				}
				else
				{
					push @html, $name eq 'textarea' ? '></textarea>' : "/>\n";
				}
			}
			
		}
		
		#print STDERR "$path [end]\n";
		
		return join '', @html;
	}


};

package AppCore::Web::Form::ModelMeta;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		#database	=> 'eas',
		table		=> 'form_model_meta',
		
		schema => 
		[
			{	field => 'modelid',	type => 'int(11)',	key => 'PRI', extra=>'auto_increment' },
			{	field => 'timestamp',	type => 'timestamp'	},
			{	field => 'uuid',	type => 'varchar(255)' },
			{	field => 'json',	type => 'longtext'},
		]
	});
	
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update(__PACKAGE__);
 	}
};

1;
