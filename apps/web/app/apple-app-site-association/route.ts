import { NextResponse } from "next/server";

export async function GET() {
  const aasa = {
    applinks: {
      apps: [],
      details: [
        {
          appID: "TA8S64ST9W.app.merian.Merian",
          paths: ["/explore/post/*"]
        }
      ]
    }
  };

  return NextResponse.json(aasa);
}
