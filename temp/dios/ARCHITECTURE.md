# DIOS technical spec

DIOS runs setup. Wizards contain the setup code.

## repos

- `dios`: Private. Runs wizards.
- `dimos`: Unchanged.
- `dimos-setup-wizard`: Open source. Installs DimOS and LCM.
- `unitree-setup-wizard`: Open source. Sets up Unitree, CycloneDDS, and its SDK.

No configurators or setup YAML.

## setup

DIOS runs the needed wizards, checks DimOS, then saves the robot.

## versioning — review question

One signed file pins DIOS, DimOS, and every wizard.

DIOS verifies it and saves the installed verisons in `dimos.lock`.

## doctor

DIOS and each wizard run their checks. Doctor shows which layer faild.
