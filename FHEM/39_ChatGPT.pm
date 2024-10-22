# $Id: 39_ChatGPT.pm 13268 2024-10-22 00:00:00Z RalfP $
###############################################################################
#
# FHEM Modul für ChatGPT 
#
###############################################################################

package main;

use strict;
use warnings;

use HttpUtils;
use JSON;
use Data::Dumper;

use constant VERSION 			=> "v0.0.1";


sub ChatGPT_Initialize($) {
	my ($hash) = @_;

	# Definieren von FHEM-Funktionen
	$hash->{DefFn}		= "ChatGPT_Define";
	$hash->{SetFn}		= "ChatGPT_Set";
	$hash->{GetFn}		= "ChatGPT_Get";
	$hash->{AttrList}	= "model:gpt-4o,gpt-4o-mini,gpt-4,gpt-3.5-turbo ";
	$hash->{AttrList}  .= $readingFnAttributes;

}

# Definition des Geräts in FHEM
sub ChatGPT_Define($$) {
	my ($hash, $def) = @_;
	my @args = split("[ \t][ \t]*", $def);

	return "Usage: define <name> ChatGPT <API-Key>" if (int(@args) != 3);

	my $name		= $args[0];
	my $apiKey	= ChatGPT_encrypt($args[2]);

	$hash->{VERSION}			= VERSION;
	$hash->{DEF} = $apiKey;
	$hash->{helper}{apiKey}	= $apiKey;
	$hash->{NAME}				= $name;
	$hash->{STATE}				= 'initialized';

	readingsSingleUpdate($hash, 'state', 'initialized', 1 );

	return undef;
}


sub ChatGPT_Set($$@) {
	my ($hash, $name, $cmd, @args) = @_;

	my $list = "ask";

	if ($cmd eq "ask") {
		
		my $question = join(' ', @args[0..$#args]);

		ChatGPT_request($hash, $question);

		readingsSingleUpdate($hash, 'state', "request", 1 );

		return undef;
	}

	return "Unknown argument $cmd, choose one of $list";
}


sub ChatGPT_request{
	my ($hash, $content) = @_;
	my $name = $hash->{NAME};
	
	my $url = "https://api.openai.com/v1/chat/completions";

	my $apiKey	= ChatGPT_decrypt($hash->{helper}{apiKey});
	
	my $auth = "Bearer $apiKey";

# Beispiel: '{ "model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Deine Nachricht hier"}]}'
	my $body = {
		model		=> AttrVal($name, 'model', 'gpt-3.5-turbo'),
		messages	=> [{role => 'user', content => $content}]
	};

	# HTTP POST Anfrage senden
	
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Authorization"		=> $auth,
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 10,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getResponse",
		"callback"		=> \&ChatGPT_parseRequestResponse,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}


sub ChatGPT_parseRequestResponse {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;

	if($err ne ""){
		Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - $err"; 
		readingsSingleUpdate($hash, 'state', 'error', 1 );
		return undef;
	}
	elsif($data ne ""){
		Log3 $name, 5, $name.": <parseRequestResponse> URL:".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";

		# $Header für Get speichern
		$hash->{helper}{header} = $param->{httpheader};
  
		# $param->{code} auswerten?
		unless (($param->{code} == 200) || ($param->{code} == 400) || ($param->{code} == 401) || ($param->{code} == 403) || ($param->{code} == 429) || ($param->{code} == 501) || ($param->{code} == 503)){
			Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			readingsSingleUpdate($hash, 'state', 'error', 1 );
			return undef;
		}

		# testen ob JSON OK ist
		if($data =~ m/\{.*\}/s){
			eval{
				$responseData = decode_json($data);
				ChatGPT_convertBool($responseData);
			};
			if($@){
				my $error = $@;
				$error =~ m/^(.*?)\sat\s(.*?)$/;
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error while JSON decode: $1 ";
				Log3 $name, 5, $name.": <parseRequestResponse> JSON decode at: $2";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
			# testen ob Referenz vorhanden
			if(ref($responseData) ne 'HASH') {
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error, response isn't a reference!";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
		}

		if ($param->{code} != 200){
			if($responseData->{error}){
				Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}." - msg: ".$responseData->{error}{message};
				readingsBeginUpdate($hash); 	
	 				readingsBulkUpdate($hash, "error_message", encode('utf8',$responseData->{error}{message}));
	 				readingsBulkUpdate($hash, "error_type", $responseData->{error}{type});
	 				readingsBulkUpdate($hash, "error_param", $responseData->{error}{param});
	 				readingsBulkUpdate($hash, "error_code", $responseData->{error}{message});
				readingsEndUpdate($hash, 1);
			}
			else{
				Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			}
			readingsSingleUpdate($hash, 'state', 'error', 1 );
			return undef;
		}		                                                      
		elsif($param->{command} eq "getResponse") { 
			$hash->{helper}{response} = $responseData;

			#$hash->{helper}{id} = $responseData->{id};
			#$hash->{helper}{object} = $responseData->{object};
			#$hash->{helper}{created} = $responseData->{created};
	 		#$hash->{helper}{model} = $responseData->{model};
	 		#$hash->{helper}{choices}{index} = $responseData->{choices}[0]{index};
	 		#$hash->{helper}{choices}{message}{role} = $responseData->{choices}[0]{message}{role};
	 		#hash->{helper}{choices}{message}{content} = $responseData->{choices}[0]{message}{content};
	 		#$hash->{helper}{usage}{prompt_tokens} = $responseData->{usage}{prompt_tokens};
	 		#$hash->{helper}{usage}{completion_tokens} = $responseData->{usage}{completion_tokens};
	 		#$hash->{helper}{usage}{total_tokens} = $responseData->{usage}{total_tokens};
	 		#$hash->{helper}{usage}{completion_tokens_details}{reasoning_tokens} = $responseData->{usage}{completion_tokens_details}{reasoning_tokens};
	 		
	 		
	 		$param->{httpheader} =~ m/^x-ratelimit-limit-requests: (.*)$/gm;
			my $x_ratelimit_limit_requests = $1;
	 		$param->{httpheader} =~ m/^x-ratelimit-limit-tokens: (.*)$/gm;
			my $x_ratelimit_limit_tokens = $1;
	 		$param->{httpheader} =~ m/^x-ratelimit-remaining-requests: (.*)$/gm;
			my $x_ratelimit_remaining_requests = $1;
	 		$param->{httpheader} =~ m/^x-ratelimit-remaining-tokens: (.*)$/gm;
			my $x_ratelimit_remaining_tokens = $1;
	 		$param->{httpheader} =~ m/^x-ratelimit-reset-requests: (.*)$/gm;
			my $x_ratelimit_reset_requests = $1;
	 		$param->{httpheader} =~ m/^x-ratelimit-reset-tokens: (.*)$/gm;
	 		my $x_ratelimit_reset_tokens = $1;
			
			readingsBeginUpdate($hash); 	
	 			readingsBulkUpdate($hash, "ID", $responseData->{id});
	 			readingsBulkUpdate($hash, "Object", $responseData->{object});
	 			readingsBulkUpdate($hash, "Created", $responseData->{created});
	 			readingsBulkUpdate($hash, "Model", $responseData->{model});
				readingsBulkUpdate($hash, "Role", $responseData->{choices}[0]{message}{role});
				readingsBulkUpdate($hash, "Content", encode('utf8',$responseData->{choices}[0]{message}{content}));
				readingsBulkUpdate($hash, "Tokens", $responseData->{usage}{total_tokens});
	 			readingsBulkUpdate($hash, "x_ratelimit_limit_requests", $x_ratelimit_limit_requests);
	 			readingsBulkUpdate($hash, "x_ratelimit_limit_tokens", $x_ratelimit_limit_tokens);
	 			readingsBulkUpdate($hash, "x_ratelimit_remaining_requests", $x_ratelimit_remaining_requests);
	 			readingsBulkUpdate($hash, "x_ratelimit_remaining_tokens", $x_ratelimit_remaining_tokens);
	 			readingsBulkUpdate($hash, "x_ratelimit_reset_requests", $x_ratelimit_reset_requests);
	 			readingsBulkUpdate($hash, "x_ratelimit_reset_tokens", $x_ratelimit_reset_tokens);
	 			readingsBulkUpdate($hash, "error_message", '');
	 			readingsBulkUpdate($hash, "error_type", '');
	 			readingsBulkUpdate($hash, "error_param", '');
	 			readingsBulkUpdate($hash, "error_code", '');
			readingsEndUpdate($hash, 1);

			readingsSingleUpdate($hash, 'state', 'finish', 1 );
		}
		else{
			Log3 $name, 5, $name.": <parseRequestResponse> unhandled command $param->{command}";
		}
		return undef;
	}
	Log3 $name, 1, $name.": error while HTTP requesting URL:".$param->{url}." - no data!";
	return undef;
}

sub ChatGPT_Get {
	my ($hash, $name, $opt, @args) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	Log3 $name, 5, $name.": <Get> called for $name : msg = $opt";

	my $dump;
	my $usage = "Unknown argument $opt, choose one of Response:noArg Header:noArg apiKey:noArg";
	
	if ($opt eq "Response"){
		if(defined($hash->{helper}{response})){
	        if(%{$hash->{helper}{response}}){
	        	ChatGPT_convertBool($hash->{helper}{response});
			    local $Data::Dumper::Deepcopy = 1;
				$dump = Dumper($hash->{helper}{response});
				$dump =~ s{\A\$VAR\d+\s*=\s*}{};
	        	return "stored data:\n".$dump;
	        }
	    }
		return "No data available: $opt";	
	} 
	elsif ($opt eq "Header"){
		if(defined($hash->{helper}{header})){
			return "Header data:\n".$hash->{helper}{header};
	    }
		return "No data available: $opt";	
	} 
	elsif($opt eq "apiKey"){
		my $apiKey = $hash->{helper}{apiKey};

		return 'no API-Key set' if( !$apiKey );

		$apiKey = ChatGPT_decrypt( $apiKey );

		return "API-Key: $apiKey";
	}

	return $usage; 
}

# Convert Bool #################################################################

sub ChatGPT_convertBool {

	local *_convert_bools = sub {
		my $ref_type = ref($_[0]);
		if ($ref_type eq 'HASH') {
			_convert_bools($_) for values(%{ $_[0] });
		}
		elsif ($ref_type eq 'ARRAY') {
			_convert_bools($_) for @{ $_[0] };
		}
		elsif (
			   $ref_type eq 'JSON::PP::Boolean'           # JSON::PP
			|| $ref_type eq 'Types::Serialiser::Boolean'  # JSON::XS
		) {
			$_[0] = $_[0] ? 1 : 0;
		}
		else {
			# Nothing.
		}
	};

	&_convert_bools;

}

# Password Crypt ###############################################################

sub ChatGPT_encrypt {
  	my ($decoded) = @_;
  	my $key = getUniqueId();
  	my $encoded;

  	return $decoded if( $decoded =~ /crypt:/ );

  	for my $char (split //, $decoded) {
    	my $encode = chop($key);
    	$encoded .= sprintf("%.2x",ord($char)^ord($encode));
    	$key = $encode.$key;
  	}

  	return 'crypt:'.$encoded;
}

sub ChatGPT_decrypt {
  	my ($encoded) = @_;
  	my $key = getUniqueId();
  	my $decoded;

  	return $encoded if( $encoded !~ /crypt:/ );
  
  	$encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  	for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    	my $decode = chop($key);
    	$decoded .= chr(ord($char)^ord($decode));
    	$key = $decode.$key;
  	}

  	return $decoded;
}

################################################################################

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;





# Beginn der Commandref ########################################################

=pod

=encoding utf8

=item device
=item summary ChatGPT provides a connection to the OpenAI API
=item summary_DE ChatGPT stellt eine Verbindung zur OpenAI API zur Verfügung

=begin html

<a name="ChatGPT" id="ChatGPT"></a>
<h3>
	ChatGPT
</h3>
<ul>
	ChatGPT provides a connection to the OpenAI API.<br />
	<br />
	A paid API key is required for this. To be created via the profile setting of your OpenAI account <a href='https://platform.openai.com'>OpenAI</a><br />
	<br />
	<a name="ChatGPT_Define" id="ChatGPT_Define"></a><b>Define</b>
	<ul>
		<code>define &lt;name&gt; ChatGPT &lt;API-Key&gt;</code><br />
		<br />
		Example: <code>define ChatGPT ChatGPT xxxxxxx</code><br />
	</ul><br />
	<a name="ChatGPT_Set" id="ChatGPT_Set"></a><b>Set</b>
	<ul>
		<li><b>ask</b><br />
			Text input.
		</li>
	</ul><br />  
	<a name="ChatGPT_Get" id="ChatGPT_Get"></a><b>Get</b>
	<ul>
		<li><b>Response</b><br />
			Show JSON response.
		</li>
		<li><b>Header</b><br />
			Show Headerof response.
		</li>
		<li><b>apiKey</b><br />
			Show API-Key (decrypted).
		</li>
	</ul><br />
</ul>

=end html

=begin html_DE

<a name="MagentaTV" id="MagentaTV"></a>
<h3>
	MagentaTV
</h3>
<ul>
	ChatGPT stellt eine Verbindung zur OpenAI API zur Verfügung.<br />
	<br />
	Ein kostenpflichtiger API-Key ist dafür notwendig. Zu Erstellen über die Profileinstellung deines OpenAI Accounts <a href='https://platform.openai.com'>OpenAI</a><br />
	<br />
	<a name="ChatGPT_Define" id="ChatGPT_Define"></a><b>Define</b>
	<ul>
		<code>define &lt;name&gt; ChatGPT &lt;API-Key&gt;</code><br />
		<br />
		Example: <code>define ChatGPT ChatGPT xxxxxxx</code><br />
	</ul><br />
	<a name="ChatGPT_Set" id="ChatGPT_Set"></a><b>Set</b>
	<ul>
		<li><b>ask</b><br />
			Texteingabe.
		</li>
	</ul><br />  
	<a name="ChatGPT_Get" id="ChatGPT_Get"></a><b>Get</b>
	<ul>
		<li><b>Response</b><br />
			Zeigt JSON Antwort an.
		</li>
		<li><b>Header</b><br />
			Zeigt Header an.
		</li>
		<li><b>apiKey</b><br />
			Zeigt API-Key an (entschlüsselt).
		</li>
	</ul><br />
</ul>

=end html_DE

=cut