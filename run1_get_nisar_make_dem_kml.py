#!/usr/bin/env python3

from pathlib import Path
import xml.etree.ElementTree as ET
import math
import subprocess


def read_kml_bounds(kml):

    print("[READ]", kml.name)

    tree = ET.parse(kml)
    root = tree.getroot()

    coords = []

    for elem in root.iter():
        tag = elem.tag.split("}")[-1]

        if tag == "coordinates":

            text = elem.text.strip()

            for p in text.split():

                lon, lat = p.split(",")[:2]

                coords.append(
                    (float(lon), float(lat))
                )


    if len(coords) == 0:
        raise RuntimeError(
            f"No coordinates in {kml}"
        )


    west=min(x[0] for x in coords)
    east=max(x[0] for x in coords)
    south=min(x[1] for x in coords)
    north=max(x[1] for x in coords)


    return west,east,south,north



def main():

    root=Path.cwd()

    raw=root/"raw"
    topo=root/"topo"

    topo.mkdir(exist_ok=True)


    kmls=sorted(
        raw.glob("*_NATIVE.kml")
    )


    if len(kmls)==0:
        raise RuntimeError(
            "No NISAR NATIVE.kml found"
        )


    W=math.inf
    E=-math.inf
    S=math.inf
    N=-math.inf


    for kml in kmls:

        w,e,s,n=read_kml_bounds(kml)

        W=min(W,w)
        E=max(E,e)
        S=min(S,s)
        N=max(N,n)



    print("\nRaw:")
    print(W,E,S,N)


    # 外扩0.3°
    margin=0.3

    W=math.floor(W*10)/10-margin
    E=math.ceil(E*10)/10+margin
    S=math.floor(S*10)/10-margin
    N=math.ceil(N*10)/10+margin


    print("\nDEM:")
    print(
        f"{W:.1f}/{E:.1f}/{S:.1f}/{N:.1f}"
    )


    with open(
        topo/"dem_region.txt",
        "w"
    ) as f:

        f.write(
            f"-R{W:.1f}/{E:.1f}/{S:.1f}/{N:.1f}\n"
        )


    cmd=[
        "make_dem.csh",
        f"{W:.1f}",
        f"{E:.1f}",
        f"{S:.1f}",
        f"{N:.1f}",
        "1"
    ]


    print("\nCommand:")
    print(" ".join(cmd))


    yes=input(
        "\nRun make_dem.csh? [y/N]: "
    )


    if yes.lower()=="y":

        subprocess.run(
            cmd,
            cwd=topo,
            check=True
        )


if __name__=="__main__":
    main()
