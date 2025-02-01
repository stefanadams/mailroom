use Mojo::Base -strict;

use Test::More;

use Mailroom::Message;
use Mojo::File qw(curfile);
use Mojo::Loader qw(data_section);
use Mojo::Log;

my $log = Mojo::Log->new(level => 'warn');

my $config = {
  'header.com' => [
    'to1' => 'to1@bar.com',
    'to2' => 'to2@bar.com',
    'to\d' => 'tod@bar.com',
    'to3' => 'to3@bar.com',
    'tomany' => ['tomany1@bar.com', 'tomany2@bar.com'],
    'tobar' => 'to1@header.com',
  ],
};
my $envelope = {
  from => 'from@envelope.com',
  to => ['to1@envelope.com', 'to2@envelope.com'],
};
my $message;

subtest 'Message' => sub {
  $message = Mailroom::Message->new(log => $log, skip_dmarc => 1, mx => 'header.com', config => $config, param => {
    envelope => $envelope,
    dkim     => {'@example.com' => 'pass'},
    email    => data_section('main', 'email.txt'),
    to       => 'John Doe <to3@header.com>',
    from     => '<service@example.com>',
    sender_ip => '3.4.5.6',
    subject  => 'Confirm your email address',
    spam_report => data_section('main', 'spam_report.txt'),
    spam_score => '0',
    charsets => {to => 'UTF-8', subject => 'UTF-8', from => 'UTF-8'},
    SPF      => 'pass',
  });
  isa_ok $message, 'Mailroom::Message';
  ### is $message->router->from->address, 'mailroom-dmarc_rejection@header.com';
  is $message->router->from->address, 'mailroom@header.com';
  is $message->router->to->[0]->address, 'tod@bar.com';
};

done_testing;

__DATA__
@@ email.txt
Received: by host.example.com with SMTP id abcdef Sun, 18 Sep 2022 22:34:16 +0000 (UTC)
Received: from mx1.example.com (unknown [3.4.5.6]) by host.example.com (Postfix) with ESMTPS id ABCDEF for <johndoe@examp.le>; Sun, 18 Sep 2022 22:34:16 +0000 (UTC)
DKIM-Signature: v=1; a=rsa-sha256; d=example.com; s=pp-dkim1; c=relaxed/relaxed; q=dns/txt; i=@example.com; t=1663540455; h=From:From:Subject:Date:To:MIME-Version:Content-Type; bh=abcdef=; b=abcdef/abcdef abcdef+abcdef+abcdef abcdef+abcdef abcdef/abcdef U/abcdef/abcdef/abcdef abcdef+UuA==;
Content-Transfer-Encoding: quoted-printable
Content-Type: text/plain; charset="UTF-8"
Date: Sun, 18 Sep 2022 15:34:15 -0700
Message-ID: <a@b>
X-PP-REQUESTED-TIME: 1663540449351
X-PP-Email-transmission-Id: abc-def
PP-Correlation-Id: abcdef
Subject: Confirm your email address
X-MaxCode-Template: ABC0001
To: John Doe <johndoe@examp.le>
From: <service@example.com>
X-Email-Type-Id: ABC0001
MIME-Version: 1.0
X-PP-Priority: 0-none-false
AMQ-Delivery-Message-Id: nullval
X-XPT-XSL-Name: nullval

 Hello, John Doe=20
Confirm your email address


Confirm your email address now to let us know it really belongs to you.


Once that's done, you're ready to receive money.


If you are unable to click the button below to confirm your email, please f=
ollow this link


Not sure why you received this email? Learn more [https://www.example.com/us=
appVersion=3D1.112.1&xt=3D123456%2C123456]


 Copyright =C2=A9 1999-2022 Example, Inc. All rights reserved. Example is loc=
ated Somewhere.=20


Example RT12345:en_US(en-US):1.0.0:abcdef123456

@@ spam_report.txt
Spam detection software, running on the system "host.example.com",
has NOT identified this incoming email as spam.  The original
message has been attached to this so you can view it or label
similar future email.  If you have any questions, see
@@CONTACT_ADDRESS@@ for details.

Content preview:  Hello, Tod Header Confirm your email address Confirm your
   email address now to let us know it really belongs to you. Once that's done,
   you're ready to receive money. [...] 

Content analysis details:   (0.0 points, 5.0 required)

 pts rule name              description
---- ---------------------- --------------------------------------------------
