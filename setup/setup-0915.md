Writing a few thoughts for how I want to plan out the build for homeserver

Context
1. we started the homeserver with just SSD in RAID 0, we had 2 volumes
2. yesterday (9/14) we acquired nvme as well 
3. want to do a clean slate setup of the system as we have hit anticipated volume till we start running out of space
3.1. Reasons for clean slate, want the code to describe the state of the system and be fully capable of achieving and supporting it 
3.2. Running into weird issues with symlinks and immich file status in the mobile app read (migration-findings.md)

Values I want the process to demonstrate
1. want to the process to be simple and fully documented in this code
1.1. this means no symlinks at all, mounting points directly configured into apps (plex and immich) to work with the desired locations directly
1.2. happy to discuss any benefits of symlinks to our setup if applicable
2. want nvme to provide speed up benefits, plex processing, photos should live within nvme; movies should live within SSD (migration-findings.md)
3. to discuss: process for booting macOS from nvme
4. error free, validated setup - running all diagnostics, validations after the setup to ensure things look good, running test suite before executing code if changes are made, running from main 
5. clean data footprint, warmstore is organized into logical folders by type of data (e.g. movies, tv shows, etc.); organize faststore logically by service (plex/, immich/ etc.) or suggest a different method that makes sense
5.1. currently the immich mobile app is having trouble reading filestorage allocated to immich (it thinks all of movies etc are also part of immich data) - hoping clean separation of folders and removal of symlinks will help solve the issue

Process i want to run
1. backup faststore and warmstore data - should finish by 3p pacific
2. read all documents (*.md)
3. execute and test code changes needed to clean up setup process (e.g. remove symlink creation, refactor directory setup in faststore etc.)
4. do a full new setup, run setup_full to 1) wipe existing data on warmstore, faststore, destroy raid 2) create and mount new RAIDs 3) install and configure plex and immich to use the new mounting points without any symlink nonsense
5. verify the setup through diagnostics, in app testing on phone and web
6. bring warmstore data back in, faststore didnt have much data so can be left out (TBD)
7. at the end of the setup: generate a generic user friendly email template that I can use to guide a new user through tailscale, immich and plex setup on their iphone and web

List of improvements - 
[short term]
1. significantly cut capabilities on migration, make them focused on small capabilities that are needed
2. remove any unwanted code/document and ensure documentation keeps up with the code changes
3. add addresses or links to plex, immich local on the home server landing page (served with tailscale, port 223 i think - TBC)
[medium term]
1. replace media processing logic with an LLM call, LLM to have websearch, notepad, terminal tools to process content and promote it from staging
2. investigate booting macOS from nvme - what are the advantages of doing so
3. investigate fast tier storage for frequent movies/shows OR if they are in HD
[long term]
1. adding the arr stack to help manage download of content to the system