# Twitter Backup

Small ruby script that backs up your tweets to a postgresql db.

## Usage

Clone this repository.

    git clone https://github.com/Prajjwal/twitter-backup.git

Copy users.yml.example to users.yml

    cd /path/to/repository
    mv users.yml.example users.yml

Go to http://dev.twitter.com/ & create a new application. Give it access to your
account. Fill in users.yml with your auth tokens and whatnot.

Create a postgres database. Create the following table. No plans to automate
this.

    CREATE TABLE tweets (
        id bigint,
        u_id bigint,
        data json
    );

Run the backup script

    ruby backup.rb <user>

Where "user" is a user defined in users.yml. If not given, it defaults to a user
called "default".

Use this at your own risk. Backup the db with pgdump on every run just to be
safe. I'm not responsible if you set fire to something with this.

## Issues

* No tests.
* Duplication. Dumps the entire json response to db, user objects get stored
  over and over again. No plans to fix this. I just want a dump of my entire
  account.
* Not ISO 9001 certified.
