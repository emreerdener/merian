import { Center } from "@mantine/core";
import { Suspense } from "react";
import { LoginCard } from "./LoginCard";

export default function LoginPage() {
  return <Center mih="100vh"><Suspense><LoginCard /></Suspense></Center>;
}
