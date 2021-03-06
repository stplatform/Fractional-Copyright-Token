// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

// Importing interface for implementation specific to ST Platform
import "../interfaces/ICopyrightGraph.sol";
import "./Queue.sol";
import "./Set.sol";

// will need to make sure this can withstand reentrancy attacks

// marked as abstracted until all functions are implemented
contract copyrightGraph is ICopyrightMaster, Queue, Set {
    address admin;

    // by default bool is false
    // tokenID -> isTokenERC1155
    // public only for testing
    mapping(uint256 => bool) _idToIsERC1155;

    // making three IDs erc 1155 compliant for testing purposes only
    function makeERC1155ForTesting() public onlyAdmin {
        _idToIsERC1155[1] = true;
        _idToIsERC1155[2] = true;
        _idToIsERC1155[3] = true;
    }

    // tokenID -> token struct for getting token information
    mapping(uint256 => Token) public _idToTokenStruct;
    uint256 tokenRegisteredCount = 0;
    uint256 totalEdgeCount = 0;

    modifier onlyAdmin() {
        require(msg.sender == admin, "User must be admin.");
        _;
    }

    modifier tokenIsNotZeroTokenIsERC1155TokenExistsOnGraph(uint256 id) {
        require(id != 0, "The token ID cannot be zero");
        require(
            _idToIsERC1155[id] == true,
            "The token is not a registered ERC 1155 token"
        );
        // timestamp will be zero if not added
        require(
            _idToTokenStruct[id].timeStamp == 0,
            "ID has allready been added to graph."
        );
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // Is there any way to make this function internal even though it is
    // an interface?

    /**
    @dev checks if two 'token' sets are subsets of one another. 
    If they are, returning the index such that the subset occurs
     */
    function isSubset(uint256 id, uint256[] memory parentTokenIds)
        public
        pure
        returns (bool, uint256)
    {
        uint256 length = parentTokenIds.length;
        if (length == 0) return (false, 0);
        else {
            for (uint256 i = 0; i < length; i++) {
                if (parentTokenIds[i] == id) return (true, i);
                if (parentTokenIds[i] == 0) break;
            }
            return (false, 0);
        }
    }

    // note that timestamp is not needed. You fetch timestamp in the function
    function insertToken(
        uint256[] memory parentIds,
        uint256[] memory parentWeights,
        uint256 id,
        uint256 weight
    )
        public
        override
        onlyAdmin
        tokenIsNotZeroTokenIsERC1155TokenExistsOnGraph(id)
    {
        require(
            parentIds.length == parentWeights.length,
            "The length of parent Ids and weights should be the same"
        );
        // how do I add set checking: I do not know how? Check as precondition?
        for (uint256 i = 0; i < parentIds.length; i++) {
            // adding to a set that will revert if there are duplicates
            Set.add(id, parentIds[i]);
            require(parentIds[i] != 0, "The token ID of a parent is zero.");
            require(
                _idToIsERC1155[parentIds[i]] == true,
                "A parent token is not a registed ERC 1155 token"
            );
            require(
                _idToTokenStruct[parentIds[i]].timeStamp != 0,
                "A parent token ID has not been added to graph"
            );
            require(
                _idToTokenStruct[parentIds[i]].weight == parentWeights[i],
                "A parent id does not cooresond to the correct weight"
            );
            require(
                _idToTokenStruct[parentIds[i]].isBlacklisted == false,
                "A parent ID is blacklisted so this process cannot continue"
            );
        }

        // counting the number of registered tokens
        tokenRegisteredCount++;
        _idToTokenStruct[id].weight = weight;
        _idToTokenStruct[id].timeStamp = block.timestamp;

        // if parentIds length is zero no edge connections need to be added
        if (parentIds.length == 0) {
            _idToTokenStruct[id].numberOfTokensBehind = 0;
        } else {
            for (uint256 i = 0; i < parentIds.length; i++) {
                Edge memory myEdge = Edge(parentIds[i], parentWeights[i]);
                _idToTokenStruct[id].edge.push(myEdge);
                // for each parent branch, the number of tokens behind are added
                _idToTokenStruct[id].numberOfTokensBehind += _idToTokenStruct[
                    parentIds[i]
                ].numberOfTokensBehind;
                // then +1 for the extra token behind for each parent
                _idToTokenStruct[id].numberOfTokensBehind++;
            }
            totalEdgeCount += parentIds.length;
        }
    }

    function insertEdges(
        uint256[] memory parentIds,
        uint256[] memory parentWeights,
        uint256 id
    ) external override onlyAdmin {
        require(id != 0, "The token ID cannot be zero");
        require(
            _idToIsERC1155[id] == true,
            "The token is not a registered ERC 1155 token"
        );
        require(
            _idToTokenStruct[id].timeStamp != 0,
            "ID has not been added to graph."
        );
        require(
            _idToTokenStruct[id].isBlacklisted == false,
            "id is blacklisted so this process cannot continue"
        );
        // if parentIds length is zero no edge connections need to be added
        if (parentIds.length == 0) return;

        for (uint256 i = 0; i < parentIds.length; i++) {
            Set.add(id, parentIds[i]);
            require(parentIds[i] != 0, "The token ID of a parent is zero.");
            require(
                _idToIsERC1155[parentIds[i]] == true,
                "A parent token is not a registed ERC 1155 token"
            );
            require(
                _idToTokenStruct[parentIds[i]].timeStamp != 0,
                "parent token ID has not been added to graph"
            );
            require(
                _idToTokenStruct[parentIds[i]].weight == parentWeights[i],
                "A parent id does not cooresond to the correct weight"
            );
            require(
                _idToTokenStruct[parentIds[i]].isBlacklisted == false,
                "A parent ID is blacklisted so this process cannot continue"
            );
        }

        // clearing the set so set can be used later

        require(
            parentIds.length == parentWeights.length,
            "The length of parent Ids and weights should be the same"
        );

        (bool isSub, ) = isSubset(id, parentIds);
        require(!isSub, "TokenID cannot be a subset of parentTokenIDs");

        // checking for redundant edge connections and graph loop
        // incrementing through all parentIds
        for (uint256 z = 0; z < parentIds.length; z++) {
            // incrementing through all current to destinations in edge
            for (uint256 e = 0; e < _idToTokenStruct[id].edge.length; e++) {
                require(
                    _idToTokenStruct[id].edge[e].to != parentIds[z],
                    "Error: Edge connection you are trying to add allready exists"
                );

                // if a parent id allready has an edge connection to id
                // adding an edge would cause an infinite loop
                require(
                    _idToTokenStruct[parentIds[z]].edge[e].to != id,
                    "Error: an graph loop will be created"
                );
            }

            // add edges if no reverts occured
            // my theory is that the struct in ICopyrightGraph behaves like non dynamic array
            // thus you cannot push an element
            //_idToTokenStruct[id].edge.to.push(parentIds[z]);
            // _idToTokenStruct[id].edge.weight.push(parentWeights[z]);
        }

        totalEdgeCount += parentIds.length;

        for (uint256 i = 0; i < parentIds.length; i++) {
            Edge memory myEdge = Edge(parentIds[i], parentWeights[i]);
            _idToTokenStruct[id].edge.push(myEdge);
            _idToTokenStruct[id].numberOfTokensBehind += _idToTokenStruct[
                parentIds[i]
            ].numberOfTokensBehind;
            _idToTokenStruct[id].numberOfTokensBehind++;
        }
    }

    function changeTokenWeight(uint256 id, uint256 newWeight)
        public
        override
        onlyAdmin
    {
        require(id != 0, "The token ID cannot be zero");
        require(
            _idToIsERC1155[id] == true,
            "The token is not a registered ERC 1155 token"
        );
        require(
            _idToTokenStruct[id].timeStamp != 0,
            "ID has not been added to graph."
        );
        require(
            !_idToTokenStruct[id].isBlacklisted,
            "id is blacklisted so this process cannot continue"
        );

        _idToTokenStruct[id].weight = newWeight;
    }

    function blacklistToken(uint256 id, bool isBlacklisted)
        public
        override
        onlyAdmin
    {
        require(id != 0, "The token ID cannot be zero");
        require(
            _idToIsERC1155[id] == true,
            "The token is not a registered ERC 1155 token"
        );
        require(
            _idToTokenStruct[id].timeStamp != 0,
            "ID has not been added to graph."
        );
        // if attempting to changing the state results in no change
        if (_idToTokenStruct[id].isBlacklisted = isBlacklisted) return;
        // changing blacklisted state
        _idToTokenStruct[id].isBlacklisted = isBlacklisted;
    }

    // question: if a token is found on a bfs traversal at least twice and has weights
    // of different values, which one is chosen? Solution: average the weights.
    // Right now, the smallest weight is chosen for the above case
    function bfsTraversal(uint256 id)
        public
        returns (uint256[] memory, uint256[] memory)
    {
        require(id != 0, "The token ID cannot be zero");
        require(
            _idToIsERC1155[id] == true,
            "The token is not a registered ERC 1155 token"
        );
        require(
            _idToTokenStruct[id].timeStamp != 0,
            "ID has not been added to graph."
        );
        require(
            !_idToTokenStruct[id].isBlacklisted,
            "id is blacklisted so this process cannot continue"
        );

        uint256 length = _idToTokenStruct[id].numberOfTokensBehind + 1;
        // uint[] memory list = new uint[](some_size);
        uint256[] memory BFSTokenList = new uint256[](length);
        uint256[] memory BFSWeightList = new uint256[](length);

        uint256 tokenCounter = 0;
        uint256 weightCounter = 0;

        // starting with the token we are located add the token to the bfs traversal
        Queue.enqueue(id);

        uint256 adjacentId;

        // if the queue is not empty go through the loop
        while (!Queue.isEmpty) {
            adjacentId = Queue.dequeue();

            // if the adjacentId is the first id we are adding to the graph
            if (adjacentId == id) {
                BFSTokenList[tokenCounter] = adjacentId;
                tokenCounter++;
                BFSWeightList[weightCounter] = _idToTokenStruct[adjacentId]
                    .weight;

                weightCounter++;
            }

            uint256 edgeLen = _idToTokenStruct[adjacentId].edge.length;
            // iterating over all of the edges connected to id

            for (uint256 i = 0; i < edgeLen; i++) {

                // checking that the ids associated with edge connections are not blacklists
                require(
                    !_idToTokenStruct[_idToTokenStruct[adjacentId].edge[i].to]
                        .isBlacklisted,
                    "An id associated with an edge connection is blacklisted"
                );

                Queue.enqueue(_idToTokenStruct[adjacentId].edge[i].to);
                // checks if a token is repeated
                // if so, index at represents where the token is repeated
                (bool isSub, uint256 indexAt) = isSubset(
                    _idToTokenStruct[adjacentId].edge[i].to,
                    BFSTokenList
                );
                if (!isSub) {
                    BFSTokenList[tokenCounter] = _idToTokenStruct[adjacentId]
                        .edge[i]
                        .to;
                    tokenCounter++;
                    BFSWeightList[weightCounter] = _idToTokenStruct[adjacentId]
                        .edge[i]
                        .weight;
                    weightCounter++;
                    // insert sort algorithm
                    // getting the value from the newest element
                    // times are in ascending order latest -> earliest
                    for (uint256 e = tokenCounter - 1; e > 0; e--) {
                        // the last token timestamp in the array to check for swap
                        uint256 key = _idToTokenStruct[BFSTokenList[e]]
                            .timeStamp;
                        uint256 j = e - 1;

                        uint256 secondToLastToken = BFSTokenList[j];
                        uint256 secondToLastWeight = BFSWeightList[j];

                        if (
                            _idToTokenStruct[secondToLastToken].timeStamp < key
                        ) {
                            // swapping the tokens and weights in the arrays
                            BFSTokenList[j] = BFSTokenList[e];
                            BFSTokenList[e] = secondToLastToken;
                            BFSWeightList[j] = BFSWeightList[e];
                            BFSWeightList[e] = secondToLastWeight;
                        } else {
                            // breaks the loop if no tokens need to be swapped
                            break;
                        }
                    }
                } else {
                    // find the minimum weight of the two tokens which have redundant edge connections
                    uint256 prevWeight = _idToTokenStruct[BFSTokenList[indexAt]]
                        .weight;
                    uint256 newWeight = _idToTokenStruct[adjacentId]
                        .edge[i]
                        .weight;
                    // recording the weight for a token as the smallest of the weights
                    if (newWeight < prevWeight) {
                        _idToTokenStruct[BFSTokenList[indexAt]]
                            .weight = newWeight;
                    }
                }
            }
        }

        // after the arrays are processed correctly, return the result
        return (BFSTokenList, BFSWeightList);
    }

    // View and Pure Functions

    function tokenExists(uint256 id)
        external
        view
        override
        returns (bool exists)
    {
        exists = false;
        if (_idToTokenStruct[id].timeStamp != 0) {
            exists = true;
        }
        return exists;
    }

    function tokenCount() public view override returns (uint256) {
        return tokenRegisteredCount;
    }

    function returnId(Token memory token)
        external
        pure
        override
        returns (uint256 id)
    {
        return 0;
    }

    function returnTokenWeight(uint256 id)
        external
        view
        override
        returns (uint256 weight)
    {
        return _idToTokenStruct[id].weight;
    }

    function returnTime(uint256 id)
        external
        view
        override
        returns (uint256 timeStamp)
    {
        return _idToTokenStruct[id].timeStamp;
    }

    function returnIsBlacklisted(uint256 id)
        external
        view
        override
        returns (bool isBlacklisted)
    {
        return _idToTokenStruct[id].isBlacklisted;
    }

    function getEdge(uint256 id) public view returns (Edge[] memory edge) {
        return _idToTokenStruct[id].edge;
    }

    function getAdmin() public view returns (address) {
        return admin;
    }

    function getTokenRegisteredCount() public view returns (uint256) {
        return tokenRegisteredCount;
    }

    function getTotalEdgeCount() public view returns (uint256) {
        return totalEdgeCount;
    }

    //  uint256 key = _idToTokenStruct[
    //                         BFSTokenList[tokenCounter - 1]
    //                     ].timeStamp;
    //                     uint256 target = _idToTokenStruct[
    //                         BFSTokenList[tokenCounter - 2]
    //                     ].timeStamp;
    //                     uint256 increment = 2;
    //                     while (key > target) {
    //                         // swapping the elements
    //                         _idToTokenStruct[BFSTokenList[tokenCounter - 1]]
    //                             .timeStamp = target;
    //                         _idToTokenStruct[BFSTokenList[tokenCounter - 2]]
    //                             .timeStamp = key;
    //                     }
    // if adjacentID isnt a subset of the list of tokens allready in BFS
    // For Example: 1 -> 2,3 and 2,3 -> 4 where there are edge connections
    // from 1 -> 2 and 1 -> 3. 1 only need to be listed once.
    // the bfs is 4, 3, 2, 1 or 4, 2, 3, 1 depending on order

    // function returnEdge(uint256 id)
    //     external
    //     view
    //     override
    //     returns (Edge[] memory edge)
    // {
    //     return _idToTokenStruct[id].edge;
    // }

    //     /**
    // @dev this function sorts a 512 uint256 sized array
    // I do not know which sorting algorithm to use so right now the function
    // does not sort
    //  */
    // function sortByTime(
    //     uint256[512] memory BFSTokenList,
    //     uint256[512] memory BFSWeightList
    // ) internal {
    //     // memory arrays are reference types
    //     for (uint256 i = 0; i < 512; i++) {
    //         if (BFSTokenList[i] == 0) break;
    //     }
    // }

    // function edgeTo(uint256 id)
    //     external
    //     view
    //     override
    //     returns (uint256[] memory)
    // {
    //     return _idToTokenStruct[id].edge.to;
    // }

    // function edgeWeights(uint256 id)
    //     external
    //     view
    //     override
    //     returns (uint256[] memory)
    // {
    //     return _idToTokenStruct[id].edge.weight;
    // }

    // function edgeCount() external view override returns (uint256) {
    //     return totalEdgeCount;
    // }

    //FUNCTIONS NOT BEING USED RIGHT NOW BUT MAY BE USED IN FUTURE

    // // id -> BFS Token search
    // // mapping from id to its breadth first search
    // // a set because of the restriction that there should be only one tokenId instance per graph
    // // useful for if you want to just update the BFS, not do the whole computation again
    // mapping(uint256 => uint256[]) _idToBFSTokenList;
    // mapping(uint256 => uint256[]) _idToBFSTokenWeightList;
    /**
    Make sure admin contains the address of the smart contract 
     */
    // function insertEdges(Token[] memory parentTokenIDs, Token memory token)
    //     public
    //     onlyAdmin
    // {
    //     require(token.id != 0, "The token ID cannot be zero");
    //     require(
    //         idToTokenStruct[token.id].id != 0,
    //         "ID has not been added to the graph."
    //     );
    //     bool isSub = isSubset(token.id, parentTokenIDs);
    //     require(!isSub, "TokenID is a subset of parentTokenIDs");
    //     uint256 length = parentTokenIDs.length;
    //     // if there are no parent token IDs
    //     if (length == 0) return;
    //     // incrementing through amt of parent token IDs
    //     for (uint256 i = 0; i < length; i++) {
    //         Edge memory edge;
    //         uint256 parentTokenID = parentTokenIDs[i].id;
    //         // loop invariant - can I just update edge each time? Is that more effiecient?
    //         // create an update edge function
    //         edge.to = token.id;
    //         edge.weight = token.weight;
    //         // registering an edge with token.ids
    //         idToEdges[token.id].push(edge);
    //     }
    // }
    // intended to also remove edges by calling another function in this one
    // // should I make it seperate instead? ask Bell
    // // Need to change the logic for this function
    // function removeToken(
    //     Token[] memory parentsOfTokenRemoved,
    //     // change to tokenID, not Token object
    //     uint256 idToRemove,
    //     Token[] memory childrenOfTokenRemoved
    // )
    //     external
    //     override
    //     onlyAdmin {
    //     // deleting the token struct for this token
    //     delete idToTokenStruct[idToRemove];
    //     // leaf token
    //     // need to delete edges from parentsOfTokenRemoved to tokenToRemove
    //     if (childrenOfTokenRemoved.length == 0) {
    //         removeCertainEdges(parentsOfTokenRemoved, idToRemove);
    //     }
    //     // root token
    //     else if (parentsOfTokenRemoved.length == 0) {
    //         // removing all edges in front of idToRemove
    //         removeAllEdges(idToRemove);
    //     } else {
    //         // removing all edges in front of token to remove
    //         removeAllEdges(idToRemove);
    //         // removing the edges behind token to remove
    //         removeCertainEdges(parentsOfTokenRemoved, idToRemove);

    //         // making the new edge connections back
    //         for (uint256 i = 0; i < childrenOfTokenRemoved.length; i++) {
    //             // inserting edges for each parent to each child of the token removed
    //             insertEdges(parentsOfTokenRemoved, childrenOfTokenRemoved[i]);
    //         }
    //     }
    // }

    // // deleting edges attributed to a certain tokenID
    // function removeAllEdges(uint256 idToRemove)
    //     public
    //     onlyAdmin
    // {
    //     delete idToEdges[idToRemove];
    // }

    // function removeCertainEdges(
    //     Token[] memory parentsOfTokenRemoved,
    //     uint256 idToRemove
    // )
    //     public
    //     onlyAdmin
    // {
    //     uint256 parentLength = parentsOfTokenRemoved.length;
    //     for (uint256 i = 0; i < parentLength; i++) {
    //         uint256 parentTokenID = parentsOfTokenRemoved[i].id;
    //         uint256 edgeArrayLength = idToEdges[parentTokenID].length;
    //         for (uint256 j = 0; j < edgeArrayLength; j++) {
    //             uint256 toID = idToEdges[parentTokenID][j].to;
    //             // if the destination is the ID to be deleted
    //             if (toID == idToRemove) {
    //                 // https://blog.finxter.com/how-to-delete-an-element-from-an-array-in-solidity/#:~:text=We%20can%20create%20a%20function,using%20the%20pop()%20method.
    //                 // firstArray[index] = firstArray[firstArray.length - 1];
    //                 // moving the element to delete to the end of the array
    //                 idToEdges[parentTokenID][j] = idToEdges[
    //                     parentTokenID
    //                 ][edgeArrayLength - 1];
    //                 idToEdges[parentTokenID].pop();
    //             }
    //         }
    //     }
    // }

    // // View Functions
    // function getEdgesInPath(uint256 id)
    //     external
    //     override
    //     view
    //     returns (Edge[] memory edges)
    // {
    //     require(id != 0, "The token ID cannot be zero");
    //     require(
    //         idToTokenStruct[id].id != 0,
    //         "ID has not been added to the graph yet."
    //     );
    //     require(idToEdges[id].length > 0, "There must be edges in the path to run this function.");

    // }

    /*   
    // tokenID -> order added (for example, tokenID 58 -> 1 and 26 -> 2 since token ID 58 was added first)
    // used for checking if tokenID is allready created 
    mapping(uint256 => uint256) idToOrderAdded;
    uint256 orderAddedCount = 1; 
    */
}
