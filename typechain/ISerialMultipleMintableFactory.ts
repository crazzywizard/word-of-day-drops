/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer } from "ethers";
import { Provider } from "@ethersproject/providers";

import type { ISerialMultipleMintable } from "./ISerialMultipleMintable";

export class ISerialMultipleMintableFactory {
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): ISerialMultipleMintable {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as ISerialMultipleMintable;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "uint256",
        name: "serialId",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "to",
        type: "address",
      },
    ],
    name: "mintSerial",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "serialId",
        type: "uint256",
      },
      {
        internalType: "address[]",
        name: "to",
        type: "address[]",
      },
    ],
    name: "mintSerials",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];