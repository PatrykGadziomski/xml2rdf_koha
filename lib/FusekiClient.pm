package FusekiClient;
use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP qw(decode_json);
use Exporter 'import';

our @EXPORT_OK = qw(dataset_exists create_dataset upload_turtle sparql_select);

# Prüft, ob ein Dataset mit gegebenem Namen bereits existiert
sub dataset_exists {
    my (%args) = @_;
    my $base   = $args{base_url};      # z.B. http://localhost:3030
    my $name   = $args{name};          # z.B. bestand
    my $user   = $args{user};
    my $pass   = $args{pass};

    my $ua = HTTP::Tiny->new;
    my %opts;
    $opts{headers}{Authorization} = 'Basic ' . _basic_auth($user, $pass)
        if defined $user;

    my $response = $ua->get("$base/\$/datasets", \%opts);
    die "Fehler beim Abfragen der Datasets: $response->{status} $response->{reason}\n"
        unless $response->{success};

    my $data = decode_json($response->{content});
    for my $ds (@{ $data->{datasets} }) {
        # ds.name kommt mit führendem "/" zurück, z.B. "/bestand"
        return 1 if $ds->{'ds.name'} eq "/$name";
    }
    return 0;
}

# Legt ein neues Dataset an (persistent via TDB2)
sub create_dataset {
    my (%args) = @_;
    my $base = $args{base_url};
    my $name = $args{name};
    my $user = $args{user};
    my $pass = $args{pass};

    my $ua = HTTP::Tiny->new;
    my %opts = (
        headers => { 'Content-Type' => 'application/x-www-form-urlencoded' },
        content => "dbName=$name&dbType=tdb2",
    );
    $opts{headers}{Authorization} = 'Basic ' . _basic_auth($user, $pass)
        if defined $user;

    my $response = $ua->post("$base/\$/datasets", \%opts);
    die "Fehler beim Anlegen des Datasets: $response->{status} $response->{reason}\n$response->{content}\n"
        unless $response->{success};

    return 1;
}

# Lädt eine Turtle-Datei in ein bestehendes Dataset hoch
sub upload_turtle {
    my (%args) = @_;
    my $base = $args{base_url};
    my $name = $args{name};
    my $file = $args{file};
    my $user = $args{user};
    my $pass = $args{pass};

    open my $fh, '<:raw', $file or die "Kann $file nicht öffnen: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;

    my %headers = ( 'Content-Type' => 'text/turtle' );
    $headers{Authorization} = 'Basic ' . _basic_auth($user, $pass)
        if defined $user;

    my $ua = HTTP::Tiny->new;
    my $response = $ua->post(
        "$base/$name/data",
        {
            headers => \%headers,
            content => $content,
        }
    );

    die "Fehler beim Hochladen: $response->{status} $response->{reason}\n$response->{content}\n"
        unless $response->{success};

    return 1;
}

sub _basic_auth {
    my ($user, $pass) = @_;
    require MIME::Base64;
    return MIME::Base64::encode_base64("$user:$pass", '');
}

# Führt eine SPARQL-SELECT-Query aus, gibt dekodiertes JSON zurück
sub sparql_select {
    my (%args) = @_;
    my $base  = $args{base_url};
    my $name  = $args{name};
    my $query = $args{query};
    my $user  = $args{user};
    my $pass  = $args{pass};

    my %headers = ( 'Accept' => 'application/sparql-results+json' );
    $headers{Authorization} = 'Basic ' . _basic_auth($user, $pass)
        if defined $user;

    my $ua = HTTP::Tiny->new;
    my $response = $ua->post_form(
        "$base/$name/sparql",
        { query => $query },
        { headers => \%headers },
    );

    die "SPARQL-Query fehlgeschlagen: $response->{status} $response->{reason}\n$response->{content}\n"
        unless $response->{success};

    return decode_json($response->{content});
}

1;