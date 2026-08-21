# dios technical spec

dios runs setup. wizards contain the setup code.

## repositories

- `dios`: private. runs wizards.
- `dimos`: unchanged.
- `dimos-setup-wizard`: open source. installs dimos and lcm.
- `unitree-setup-wizard`: open source. sets up unitree, cyclonedds, and its sdk.

no configurators or setup yaml.

## setup

dios runs the needed wizards, checks dimos, then saves the robot.

## versioning — review question

one signed file pins dios, dimos, and every wizard.

dios verifies it and saves the installed verisons in `dimos.lock`.

## doctor

dios and each wizard run their checks. doctor shows which layer faild.
